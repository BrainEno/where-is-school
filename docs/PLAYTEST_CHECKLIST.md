# Playtest checklist — the Windows build

The point of this list is to be played *once, in order, writing things down as you go*.
It exists because the build is the first time the slice can be played as a player: up to
the release round, every milestone was verified by headless tests and by the capture
workflow, and every pull request said "Windows hands-on checks are not yet performed".
Automated checks can prove a door works; they cannot say whether the yard is boring.

Use the build from the `where-is-school-windows` artifact of the release workflow (or the
GitHub release, if one exists). Record at the top:

| Field | Value |
|---|---|
| Build | zip name, or the commit the artifact came from |
| Date | |
| Machine / GPU / RAM | |
| Resolution, windowed or full screen | |
| Language played in | English / 简体中文 |
| Time to reach the end card | |

## 1. Before the game

- [ ] The zip unpacks to an `.exe`, `HOW-TO-RUN.txt` and `licences/`. Nothing else.
- [ ] Double-click the `.exe`. Windows warns about an unknown publisher — "More info" →
      "Run anyway". If Defender *quarantines* it instead of warning, write that down: it
      is the difference between "unsigned" and "looks like malware", and the second one
      needs a code-signing decision before anyone else is given a build.
- [ ] The window opens at 1280×720 and the first frame is the classroom, not a grey screen.
- [ ] Close and reopen: the language you picked last time is still picked.

## 2. Does it feel like a game (classroom)

- [ ] Walk with WASD, then with the arrow keys. Neither feels like sliding; the camera
      keeps the same framing.
- [ ] Click the floor: the character walks there, stops without jitter at the end, and a
      small mark (a few uneven strokes, not a ring) sits on the spot the click was
      accepted on. It does not turn or breathe while the character walks, and it fades
      when the walk ends. Check it on the ramp and on a step: it lies on the surface.
- [ ] Click a wall, a desk top and the doorway floor. The first two should refuse, the
      doorway should walk.
- [ ] Hover the schoolbag, the bed, the door, the noticeboard: the cursor changes and the
      prompt names the object. Then press **E** without moving: the *same* object is used.
- [ ] Read the opening. Text is not clipped at the band's edges, the speaker's name is
      above the line, and the line finishes rather than jumping when you press Space
      twice quickly.
- [ ] Open the log with Tab mid-conversation, close it with Esc, and continue: the line is
      where you left it.
- [ ] Press **L** while a sentence is on screen. The sentence switches language in place,
      without losing your place, and the interface follows.

## 3. The way out, and the free period

- [ ] Leave the classroom; in the walkway the announcement plays and the free-period
      choice appears. Pick **stay** once: the classroom stays playable and nothing forces
      you out. (There is no need to replay — note whether "stay" *felt* like a real option.)
- [ ] Pick **leave** and use the walkway's optional things: the wall speaker (a short
      exchange, with the noise of a class behind the wall playing over it — listen for
      whether the cue lands before or after the line), the cleaning trolley, the railing.
- [ ] Reach the yard through the walkway's end door. Also try the street route (the long
      way round) from a fresh run if you have the patience.

## 4. The street and the courtyard

- [ ] Street: the stair prompt names the stairs and not the wall behind them; the
      notice pole and lamp post can both be inspected.
- [ ] Courtyard: the **bench** is the authored model, its back is to the open courtyard
      and its seat faces the planter. Standing anywhere in front of it, the prompt appears
      (this is the anchor move from the props round — if it is unreachable from one side,
      note which side).
- [ ] The green animal: approach and talk. It offers no check — note only whether it says
      something you did not already know from the courtyard itself.
- [ ] Walk the courtyard's north gap into the alley and back. Both directions, no snagging
      on the lintel, no falling through.

## 5. The yard

- [ ] Enter from the alley gate. Walk the whole perimeter once without the minimap (there
      is none): can you tell where the exits are?
- [ ] The **bench and the bag**: the bag sits on the seat, upright, square with the bench,
      leaning into the back — no floating, no sinking, no intersection with the slats.
- [ ] Inspect the bench. The text says a bag is on it and that the seat is wet: note
      whether the wetness is visible (it is not modelled — this is a known gap, listed so
      you can judge whether it matters).
- [ ] The climbing frame, the hoop, the shed, the container, the tyres, the fitness gear,
      the birds on the fence: each should have a prompt and a readable line. Count how
      many felt worth reading.
- [ ] **A visible check**: the shed door and the ball both offer one. The numbers should
      be on screen, the choice should be clear, and the outcome should say what happened.
      Then try the same thing again: does the game let you re-roll it for free?
- [ ] **A hidden check**: the inner voice runs one on arriving in the yard, at the notice
      board and at the hoop. Only the reaction is shown, never the numbers — note whether
      that reads as a judgement or as the game being coy. Note how often the voice fires
      while you walk, and whether it ever interrupts something you were reading.
- [ ] Reach `pg_gap_in_fence`: the end card appears, the movement locks, and the card can
      be read in full without the HUD fighting it.

## 6. Being difficult on purpose

- [ ] Alt-Tab away for a minute and come back: the game is still running, not frozen.
- [ ] Resize the window (or maximise) during a conversation: the reading band stays
      readable and the options stay clickable.
- [ ] Press **F11** mid-conversation: the game goes fullscreen, the dialogue keeps its
      place (same line, same typing progress), the character does not move and the room
      does not reload. Press it again: the window comes back the same size and in the
      same place it was. Hold F11 down: it must not flicker between the two.
- [ ] Drag the window to 1280×720 (the smallest it goes): the objective line, the prompt
      and the dialogue options are all still readable and clickable, and the type has not
      shrunk to make them fit.
- [ ] Click wildly during a transition (through a door): the game must not end up in two
      rooms, and the player must not end up outside the geometry.
- [ ] Switch language, then inspect something with a long line: no missing characters
      (boxes), no clipped final punctuation.
- [ ] Quit with Alt+F4 and relaunch: no crash, no leftover window, and the game starts from
      the beginning (there is no save system yet).

## 7. Frame rate

No profiler is needed for a first pass. Note the *worst* room, not the average:

| Room | Feels smooth / stutters | Notes |
|---|---|---|
| Classroom | | |
| Walkway | | |
| Street | | |
| Courtyard | | |
| Alley | | |
| Yard | | |

If anything stutters, note whether it happens on entering the room (bake, one-off) or
continuously (per-frame), and whether it goes away after a second.

## 8. The three questions worth answering

Write a paragraph each, in your own words. These are the only questions the automated
suite cannot answer, and the next round of work depends on them:

1. **Where did you get bored?** The exact room and the exact moment is more useful than a
   rating.
2. **Where did you not know what to do?** A door, a person or an object you had to hunt
   for, or a line that did not tell you what it wanted to.
3. **What did you want to do that the game refused?** Walk somewhere, ask something, pick
   an option that was not offered.

Anything that broke belongs in an issue with the room, what you did and what happened; the
build has no telemetry and sends nothing anywhere, so this checklist is the only record.
