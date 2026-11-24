// Opt-in author exchange: native UIKit selection/composition and export-as-copy.
// The protocol carries UTF-8 text or ZIP bytes encoded as text, never file paths or code.
#import <UIKit/UIKit.h>
#include <fcntl.h>
#include <unistd.h>

static constexpr NSUInteger requestLimit = 2 * 1024 * 1024;
static constexpr NSUInteger fieldLimit = 8000; // Unicode scalar count, the same as Godot String.

@interface WISAuthorEditSheet : UIViewController
@property(nonatomic, copy) NSString *caption;
@property(nonatomic, copy) NSString *initialText;
@property(nonatomic, copy) BOOL (^complete)(NSString *); // nil means cancel
@end

@implementation WISAuthorEditSheet {
    UILabel *_heading;
    UITextView *_editor;
}

- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:52].active = YES;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:48].active = YES;
    return button;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.15];
    UIView *card = [UIView new];
    card.backgroundColor = UIColor.secondarySystemBackgroundColor;
    card.layer.cornerRadius = 12;
    card.clipsToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:card];

    _heading = [UILabel new];
    _heading.text = self.caption;
    _heading.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    UIButton *cancel = [self button:@"取消" action:@selector(cancel)];
    UIButton *apply = [self button:@"应用" action:@selector(apply)];
    UIStackView *bar = [[UIStackView alloc] initWithArrangedSubviews:@[_heading, cancel, apply]];
    bar.alignment = UIStackViewAlignmentCenter;
    bar.spacing = 6;
    [_heading setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:bar];

    _editor = [UITextView new];
    _editor.backgroundColor = UIColor.systemBackgroundColor;
    _editor.textColor = UIColor.labelColor;
    _editor.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _editor.adjustsFontForContentSizeCategory = YES;
    _editor.text = self.initialText;
    _editor.accessibilityLabel = self.caption;
    _editor.smartQuotesType = UITextSmartQuotesTypeNo;
    _editor.smartDashesType = UITextSmartDashesTypeNo;
    _editor.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_editor];

    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    NSLayoutConstraint *aboveKeyboard = [card.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-8];
    aboveKeyboard.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:safeArea.topAnchor constant:8],
        [card.bottomAnchor constraintLessThanOrEqualToAnchor:safeArea.bottomAnchor constant:-8],
        [card.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor constant:-8],
        [card.widthAnchor constraintEqualToAnchor:safeArea.widthAnchor multiplier:0.58],
        aboveKeyboard,
        [bar.topAnchor constraintEqualToAnchor:card.topAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:10],
        [bar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-6],
        [_editor.topAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [_editor.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:8],
        [_editor.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-8],
        [_editor.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-8],
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_editor becomeFirstResponder];
}

- (void)endWithText:(NSString *)text {
    if (!self.complete || !self.complete(text)) {
        _heading.text = @"保存失败，请重试";
        return;
    }
    [_editor resignFirstResponder];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)cancel { [self endWithText:nil]; }

- (void)apply {
    [_editor unmarkText];
    NSString *text = _editor.text ?: @"";
    if ([text lengthOfBytesUsingEncoding:NSUTF32LittleEndianStringEncoding] / 4 > fieldLimit) {
        _heading.text = @"最多 8000 字符";
        return;
    }
    [self endWithText:text];
}
@end

@interface WISAuthorFiles : NSObject <UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate>
@end

@implementation WISAuthorFiles {
    NSURL *_inbox;
    NSURL *_temporary;
    NSString *_activeID;
    UIDocumentPickerViewController *_picker;
    WISAuthorEditSheet *_sheet;
    dispatch_source_t _watch;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    NSFileManager *fs = NSFileManager.defaultManager;
    NSURL *documents = [fs URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    _inbox = [[documents URLByAppendingPathComponent:@"story_editor" isDirectory:YES]
        URLByAppendingPathComponent:@"share" isDirectory:YES];
    if (!_inbox || ![fs createDirectoryAtURL:_inbox withIntermediateDirectories:YES attributes:nil error:nullptr]) {
        return nil;
    }
    // A request from an app killed before presentation is not a new user gesture.
    [fs removeItemAtURL:[_inbox URLByAppendingPathComponent:@"request.json"] error:nullptr];
    [fs removeItemAtURL:[_inbox URLByAppendingPathComponent:@"result.json"] error:nullptr];
    const int fd = open(_inbox.fileSystemRepresentation, O_EVTONLY | O_CLOEXEC);
    if (fd < 0) return nil;
    _watch = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fd, DISPATCH_VNODE_WRITE,
                                    dispatch_get_main_queue());
    if (!_watch) {
        close(fd);
        return nil;
    }
    __weak WISAuthorFiles *weakSelf = self;
    dispatch_source_set_event_handler(_watch, ^{ [weakSelf checkRequest]; });
    dispatch_source_set_cancel_handler(_watch, ^{ close(fd); });
    dispatch_resume(_watch);
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(becameActive:)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    return self;
}

- (void)dealloc {
    if (_watch) dispatch_source_cancel(_watch);
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (_temporary) [NSFileManager.defaultManager removeItemAtURL:_temporary error:nullptr];
}

- (UIViewController *)presenter {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow && !window.hidden) {
                UIViewController *controller = window.rootViewController;
                return (controller.viewIfLoaded.window && !controller.presentedViewController) ? controller : nil;
            }
        }
    }
    return nil;
}

- (void)becameActive:(NSNotification *)notification {
    (void)notification;
    [self checkRequest];
}

- (void)checkRequest {
    if (_picker || _sheet || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    NSURL *request = [_inbox URLByAppendingPathComponent:@"request.json"];
    NSNumber *size = nil;
    if (![request getResourceValue:&size forKey:NSURLFileSizeKey error:nullptr] || size.unsignedIntegerValue > requestLimit) return;
    NSData *packet = [NSData dataWithContentsOfURL:request];
    if (!packet || packet.length > requestLimit) return;
    id object = [NSJSONSerialization JSONObjectWithData:packet options:0 error:nullptr];
    [NSFileManager.defaultManager removeItemAtURL:request error:nullptr];
    if (![object isKindOfClass:NSDictionary.class]) return;
    id identifier = object[@"id"];
    id text = object[@"text"];
    id kind = object[@"kind"];
    if (![identifier isKindOfClass:NSString.class] || [identifier length] != 31 ||
        ![text isKindOfClass:NSString.class] || ![kind isKindOfClass:NSString.class]) return;
    _activeID = identifier;
    UIViewController *controller = [self presenter];
    if (controller && [kind isEqualToString:@"export"]) {
        [self exportText:text from:controller];
    } else if (controller && [kind isEqualToString:@"chapter"]) {
        NSData *zip = [[NSData alloc] initWithBase64EncodedString:text options:0];
        const unsigned char *bytes = static_cast<const unsigned char *>(zip.bytes);
        if (zip.length < 4 || bytes[0] != 'P' || bytes[1] != 'K' || bytes[2] != 3 || bytes[3] != 4) {
            [self finishPicker:@"error"];
            return;
        }
        [self exportBytes:zip name:@"where-is-school-chapter-candidate.zip" from:controller];
    } else if (controller && [kind isEqualToString:@"edit"]) {
        id caption = object[@"caption"];
        [self editText:text caption:[caption isKindOfClass:NSString.class] ? caption : @"编辑文案" from:controller];
    } else {
        [self finishPicker:@"error"];
    }
}

- (void)exportText:(NSString *)text from:(UIViewController *)controller {
    [self exportBytes:[text dataUsingEncoding:NSUTF8StringEncoding]
        name:@"where-is-school-dialogue-draft.json" from:controller];
}

- (void)exportBytes:(NSData *)data name:(NSString *)name from:(UIViewController *)controller {
    _temporary = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    NSURL *copy = [_temporary URLByAppendingPathComponent:name];
    if (!data || ![NSFileManager.defaultManager createDirectoryAtURL:_temporary
            withIntermediateDirectories:YES attributes:nil error:nullptr] ||
        ![data writeToURL:copy options:NSDataWritingAtomic error:nullptr]) {
        [self finishPicker:@"error"];
        return;
    }
    _picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[copy] asCopy:YES];
    _picker.delegate = self;
    _picker.presentationController.delegate = self;
    [controller presentViewController:_picker animated:YES completion:^{ [self receipt:@"presented" text:nil]; }];
}

- (void)editText:(NSString *)text caption:(NSString *)caption from:(UIViewController *)controller {
    _sheet = [WISAuthorEditSheet new];
    _sheet.caption = caption;
    _sheet.initialText = text;
    _sheet.modalPresentationStyle = UIModalPresentationOverFullScreen;
    _sheet.modalPresentationCapturesStatusBarAppearance = NO;
    __weak WISAuthorFiles *weakSelf = self;
    _sheet.complete = ^BOOL(NSString *result) { return [weakSelf finishEditing:result]; };
    [controller presentViewController:_sheet animated:NO completion:^{ [self receipt:@"presented" text:nil]; }];
}

- (BOOL)receipt:(NSString *)state text:(NSString *)text {
    if (!_activeID) return NO;
    NSDictionary *packet = @{@"id": _activeID, @"state": state, @"text": text ?: @""};
    NSData *json = [NSJSONSerialization dataWithJSONObject:packet options:0 error:nullptr];
    return [json writeToURL:[_inbox URLByAppendingPathComponent:@"result.json"] options:NSDataWritingAtomic error:nullptr];
}

- (BOOL)finishEditing:(NSString *)text {
    if (![self receipt:(text ? @"edited" : @"cancelled") text:text]) return NO;
    _activeID = nil;
    _sheet = nil;
    return YES;
}

- (void)finishPicker:(NSString *)state {
    [self receipt:state text:nil];
    _activeID = nil;
    _picker = nil;
    if (_temporary) [NSFileManager.defaultManager removeItemAtURL:_temporary error:nullptr];
    _temporary = nil;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (controller == _picker) [self finishPicker:(urls.count ? @"exported" : @"cancelled")];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    if (controller == _picker) [self finishPicker:@"cancelled"];
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)controller {
    if (controller.presentedViewController == _picker) [self finishPicker:@"cancelled"];
}
@end

static WISAuthorFiles *bridge;

void wis_author_files_start() {
    dispatch_async(dispatch_get_main_queue(), ^{ bridge = [WISAuthorFiles new]; });
}

void wis_author_files_stop() {
    dispatch_async(dispatch_get_main_queue(), ^{ bridge = nil; });
}
