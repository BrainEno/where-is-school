"""Original, deliberately different fits. Labels are review descriptors, not story names."""

from dataclasses import dataclass


@dataclass(frozen=True)
class Design:
    label: str
    height: float
    crown_room: float
    body_mix: tuple[tuple[str, float], ...]
    head_targets: dict[str, float]
    cheek: tuple[str, float]
    ear: float
    body_width: float
    head_lead: float
    skin: str
    lip: str
    hair: tuple[str, str]
    brows: str
    gaze: tuple[float, float]
    shirt: str
    seam: str
    pants: str
    shoe: str
    # Hip, waist, rib cage and shoulder circumference (elliptic half-width/depth in m).
    cut: tuple[tuple[float, float], ...]
    trousers_fit: float
    arm_fit: float


ACTING = {'thin_classmate': ('mutter', 1.34), 'gentle_classmate': ('listen_offer', 1.78),
          'court_classmate': ('check_court', 1.42)}

DESIGNS = {
    'thin_classmate': Design(
        'Thin Classmate', 1.60, .021,
        (('minmuscle-minweight', .83), ('averagemuscle-minweight', .17)),
        {'head/head-oval': .30, 'head/head-scale-horiz-decr': .12,
         'chin/chin-width-decr': .30, 'chin/chin-prominent-incr': .15,
         'nose/nose-scale-vert-incr': .16, 'nose/nose-point-down': .12,
         'neck/neck-scale-horiz-decr': .28,
         'expression/units/asian/mouth-compression': .31,
         'expression/units/asian/mouth-depression': .24,
         'expression/units/asian/eyebrows-left-inner-up': .33,
         'expression/units/asian/eye-left-opened-up': .19,
         'expression/units/asian/eye-right-opened-up': .13},
        ('volume-decr', .62), .32, .90, .026, 'baa087', '976a63',
        ('24222b', '514551'), '392d30', (-.15, -.034),
        '89969c', '647982', '4a4b50', '444549',
        ((.143, .092), (.128, .082), (.145, .085), (.151, .073)), .93, .95,
    ),
    'gentle_classmate': Design(
        'Gentle Classmate', 1.62, .018,
        (('minmuscle-averageweight', .43), ('minmuscle-maxweight', .35),
         ('averagemuscle-averageweight', .22)),
        {'head/head-round': .25, 'chin/chin-height-decr': .24,
         'chin/chin-width-incr': .16, 'chin/chin-prominent-decr': .14,
         'nose/nose-scale-vert-decr': .22, 'nose/nose-point-width-incr': .16,
         'expression/units/asian/mouth-corner-puller': .32,
         'expression/units/asian/mouth-elevation': .12,
         'expression/units/asian/eye-left-opened-up': .21,
         'expression/units/asian/eye-right-opened-up': .26},
        ('volume-incr', .51), -.12, 1.00, .002, 'c89370', 'a6695e',
        ('25262a', '4e4650'), '3b3030', (.055, .02),
        'c9beb0', '9b8a80', '4b5256', '6b5246',
        ((.168, .111), (.177, .122), (.172, .105), (.164, .089)), 1.09, 1.10,
    ),
    'court_classmate': Design(
        'Court Classmate', 1.80, .042,
        (('maxmuscle-averageweight', .62), ('averagemuscle-averageweight', .38)),
        {'head/head-diamond': .30, 'head/head-scale-horiz-decr': .16,
         'chin/chin-prominent-incr': .21, 'chin/chin-width-decr': .12,
         'nose/nose-hump-incr': .22, 'nose/nose-scale-depth-incr': .18,
         'neck/neck-scale-horiz-incr': .23,
         'expression/units/asian/eye-right-slit': .22,
         'expression/units/asian/eye-left-opened-up': .13,
         'expression/units/asian/eyebrows-left-extern-up': .32,
         'expression/units/asian/eyebrows-right-down': .12,
         'expression/units/asian/mouth-corner-puller': .095,
         'expression/units/asian/mouth-compression': .115},
        ('volume-decr', .43), -.10, 1.05, .008, 'a8785e', '86594d',
        ('261f29', 'bc5446'), '3c2930', (-.123, .064),
        '9f302e', 'eeceaf', '424550', '413e46',
        ((.175, .108), (.160, .097), (.188, .113), (.195, .097)), 1.13, 1.16,
    ),
}
