# Midnight Hollow – Game Story

Oct 23, 2026 · @Börje Granberg

## Premise

On Hollow's Eve, the vampire Count Vesper Morrow steals the Harvest Moon Lantern that keeps the Harvest Moon shining over the village of Midnight Hollow. Pip, a kid in a patched witch hat, has until the clock strikes twelve to refill the Lantern with twenty glowing jack-o'-lanterns from each haunted place and take it back.

The tone is spooky but friendly: a trick-or-treat adventure, not a horror game. Each level is a different Halloween setting, lit by a different hour of the night, and the story pushes the player forward through short text screens between levels.

## Characters

| Character | Role | Look (as on screen) |
| --- | --- | --- |
| Pip | Hero, age 11, the only kid in the Hollow brave enough to go after the Count | Patched black witch hat with a yellow band, cyan cape, pumpkin pail |
| Count Vesper Morrow | Villain. Steals the Lantern so the night never ends and he can rule the Hollow | Pale vampire in a red cloak, seen first as a portrait in the mansion |
| Grandma Hazel | Guide. Runs the candy shop and sends Pip off with a pail and a plan | Appears only on the story screens, as a face and a few lines of text |
| The Night Crew | Enemies: bats, ghosts, zombies, skeletons and spiders, all working for the Count | Each type has its own movement pattern |

## The story

**Prologue, 9 PM.** Every Hollow's Eve, the village of Midnight Hollow lights the Harvest Moon Lantern in the square, and its glow keeps the moon bright until sunrise. This year, as the children line up for sweets, a bat swoops down from the mansion on the hill and snatches the Lantern. A voice rolls across the rooftops: "Let the night be mine forever." Count Vesper Morrow has been asleep for a hundred years, and he is hungry for a night that never ends.

**Act 1, the quest.** The grown-ups hide indoors. Grandma Hazel gives Pip her old pumpkin pail and tells the one thing she knows: the Lantern burns on the glow of jack-o'-lanterns, and the Count's creatures have scattered them across the Hollow to keep them out of reach. Pip must gather twenty in each place to carry enough light to the next.

**Act 2, deeper into the dark.** The graveyard gives up its first pumpkins and a rusty gate key. The woods, the mansion and the clock tower follow, each one darker than the last. In the mansion, Pip finds the Count's portrait. Its painted eyes follow Pip and a note on the frame reads: "Midnight is my hour. Be quick, little one." The golden key on the top shelf opens the way to the clock tower.

**Act 3, midnight.** In the clock tower the hands crawl toward twelve. At the top, a door leads to the Moon Chamber, where the Count waits with the Lantern, now dim and cold. Pip must set the pumpkins into its frame one by one while the Count turns into a swarm of bats and attacks. When the last pumpkin is lit, the Lantern flares, the Count shrinks into his portrait, and the moon rises full over the Hollow.

**Epilogue.** The clock strikes twelve. The village gathers around the relit Lantern and the children finally get their candy. In the last frame, the Count's portrait winks, and a new bat leaves the window. The Hollow will need Pip again next year.

## Levels

The two mockups on the canvas are levels 1 and 3. The time in the story moves from 9 PM to midnight across the five levels.

| # | Level | Story time | Goal | Enemies | Level feature |
| --- | --- | --- | --- | --- | --- |
| 1 | The Graveyard | 9 PM | 20 pumpkins, find the exit gate | Bats, ghosts, zombies, spiders | Stone platforms, moon, haunted house in the background |
| 2 | The Crooked Woods | 10 PM | 20 pumpkins, cross the swamp | Bats, spiders, crows | Rope bridges, crooked trees, fog |
| 3 | The Mansion | 10:45 PM | 20 pumpkins and the golden key | Ghosts, skeletons, bats, spiders | Wooden shelves, the Count's portrait, a grandfather clock |
| 4 | The Clock Tower | 11:30 PM | Climb to the top before midnight | Bats, gargoyles, ghosts | Moving gears and swinging pendulums as platforms |
| 5 | The Moon Chamber | 11:59 PM | Light the Lantern, defeat the Count | The Count and his bat swarm | Boss fight, six empty Lantern slots to fill |

## Story in the game

The C64 text screen is 40 characters wide, so the story is told in short screens. These are written to fit.

**Intro screen**

```
          MIDNIGHT HOLLOW

 TONIGHT THE COUNT STOLE THE HARVEST
 MOON LANTERN. WITHOUT ITS LIGHT, THE
 NIGHT WILL NEVER END.

 TAKE MY PAIL, PIP. FIND THE GLOWING
 PUMPKINS AND RELIGHT THE LANTERN
 BEFORE MIDNIGHT.

                   - GRANDMA HAZEL

         PRESS FIRE TO START
```

**Level cards**

| Level | Card text |
| --- | --- |
| 1 | 9 PM. THE GRAVEYARD. THE DEAD ARE RESTLESS TONIGHT. |
| 2 | 10 PM. THE CROOKED WOODS. SOMETHING WATCHES FROM THE TREES. |
| 3 | 10:45 PM. THE MANSION. THE PORTRAIT'S EYES FOLLOW YOU. FIND THE GOLDEN KEY. |
| 4 | 11:30 PM. THE CLOCK TOWER. THE HANDS ARE MOVING. HURRY! |
| 5 | 11:59 PM. THE MOON CHAMBER. LIGHT THE LANTERN. |

**In-play messages**

- Pumpkin collected: a short chime, and the CANDY counter goes up (e.g. 07/20).
- Twentieth pumpkin: the exit opens with the text "THE WAY IS OPEN".
- Key collected: "GOLDEN KEY! THE TOWER DOOR OPENS."
- Life lost: the hat drops, the screen flashes, and Pip restarts at the last checkpoint.

**Game over**

```
         THE NIGHT NEVER ENDS...

     THE COUNT LAUGHS IN THE DARK.

          TRY AGAIN, PIP?
```

**Ending**

```
   THE CLOCK STRIKES TWELVE. THE LANTERN
   BURNS BRIGHT AND THE MOON RISES OVER
   THE HOLLOW. THE CHILDREN GET THEIR
   CANDY AT LAST.

   WELL DONE, PIP!
```

After the ending text, the Count's portrait appears and winks, with a new bat flying out of the frame. It hints at a sequel.
