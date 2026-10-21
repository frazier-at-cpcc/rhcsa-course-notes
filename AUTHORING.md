# Authoring Guide

How to write a topic for the RHCSA course notes so it matches the rest of the
series. Read two or three finished topics in `content/` before writing
anything; the layout and voice should be indistinguishable from them.

## Voice

The notes follow the study-guide format of short bullet fragments, not prose.

- Top-level bullets state a fact or concept in a few words. Sub-bullets add the
  detail, an example, or the consequence. Two levels, never three.
- Write fragments, not full sentences, except inside callouts.
- Every sentence is original. Do not paraphrase CompTIA CertMaster, Professor
  Messer, vendor docs, or any other study guide.
- Concrete over generic: name the real flag, the real error text, the real file.
- Examples come from real system administration: a web server's document
  root, a shared project directory, a data volume running out of space, a
  service that will not start after a reboot. Hosts are servera and serverb in
  lab.example.com; users and groups have ordinary names (alice, bob, devops).

## Facts

- The notes target RHEL 10. Check behavior that changed between releases
  before writing it (RHEL 10 drops network-scripts ifcfg files entirely, uses
  `nmcli` keyfiles, ships Flatpak, and uses `grubby` with BLS entries). When a
  RHEL 9 habit no longer works on RHEL 10, say so in a bullet.
- Use the commands and options Red Hat documents for RHEL 10. If an option
  is deprecated, show the current one.
- The exam grades end state and persistence. Every configuration topic says
  how the change survives a reboot, and the test proves it where it can
  (`vm_reboot`).

## Topic file

One Markdown file per topic under `content/domain-N/`, named
`<objective>-<slug>.md`, for example `1.3-iac-principles.md`.

```markdown
---
objective: 1.3
title: Infrastructure as Code Principles
---

### First subheading
- Bullet
  - Sub-bullet
```

- `title` is Title Case and appears in the purple topic bar, the contents page,
  and the PDF bookmarks.
- Use `###` for subheadings. Each topic has 3 to 7 of them.
- Target 1.5 to 2.5 printed pages per topic.
- Cover every leaf term the objective lists. Use the objective's own wording
  for the term somewhere on the page so a student can match it to the
  objectives PDF.

## Markup

| Need | Syntax |
|---|---|
| Must-know term (yellow highlighter) | `==term==` |
| Inline command, file, flag | `` `git fetch` `` |
| Terminal session | a ` ```console label="Terminal" ` fence; lines starting with `$ ` are commands, the rest is output |
| File contents | a ` ```yaml label="playbook.yml" ` fence (any language highlight.js knows) |
| Figure in one column | `:::figure my-figure.svg \| Caption` |
| Figure across both columns | `:::figure wide my-figure.svg \| Caption` |
| Table across both columns | wrap the table in `:::wide` and `:::` |
| Exam tips (end of every topic) | `:::exam` ... `:::` |
| Hands-on exercise | `:::try` ... `:::` or `:::try Custom Label` |

Highlighter rules: 2 to 5 `==terms==` per subheading, only for vocabulary the
exam expects a student to recognize. Never highlight a whole sentence.

Tables: keep them to 2 to 4 columns. A table that needs more than about 45
characters per row goes in `:::wide`.

Every topic ends with one `:::exam` callout of 2 or 3 bullets describing how
the topic shows up in a question: the scenario wording, the distractor, the
distinction being tested.

## Code and output must be real

Every code block and every line of terminal output in the notes comes from a
real run, and a test script can reproduce it. The tests are run by hand or from
the manual Command tests workflow; they do not gate the PDF build.

- Put the script in `tests/<objective>-<slug>.sh`. It must be self-contained:
  `set -euo pipefail`, work in `mktemp -d`, clean up with `trap`, never touch
  the user's real config (`export GIT_CONFIG_GLOBAL=...` and the like), and end
  by printing `ALL <objective> <SLUG> CHECKS PASSED`.
- Assert the specific output the notes show (`grep -q`, exact comparisons), so a
  rerun shows when a tool has changed its behavior.
- Console output in the notes is copied from a real run. You may trim lines
  (drop noise, shorten a path), but never retype or "improve" output.
- When something cannot be executed here (registering with the Red Hat CDN,
  a console-only boot step), do not put it in a code block as if it ran.
  Present it as a numbered list or a table, and say in the test what was
  left out.
- Two sources of real output:
  - `tests/lib/container.sh`: an AlmaLinux 10 container (a RHEL 10
    rebuild). Use it for shell tools, text processing, archives,
    permissions, users and groups, scripting, and dnf. Each topic gets a test
    script in `tests/` that reruns its commands.
  - `lab/`: capture scripts for everything that needs a full system
    (storage, LVM, services, targets, the journal, networking, firewalld,
    SELinux, the boot loader). `lab/run.sh` runs them on a disposable RHEL 10
    VM, reboots it to prove persistence, and writes each session to
    `lab/results/<topic>.md`. Write those topics from the captured results;
    to change what a topic shows, change its script in `lab/topics/` and
    rerun it (see `lab/README.md`).
- Show commands the way a student types them on the exam: a regular user
  with `sudo`, or a root shell when the task needs one. The prompt in console
  blocks is always `$ `; write `sudo` explicitly.
- Anything that needs a console or a password prompt at boot (interrupting
  GRUB, `rd.break`, resetting the root password) cannot be scripted; show the
  steps as a numbered list or table and test what can be tested around it
  (for example the `grubby` arguments or the `/.autorelabel` file).
- State any tool beyond bash, docker, and the helpers in a `# Needs:` comment.
- Not every topic needs a long session. Short, focused console blocks that
  show the command and the one line of output that matters read better than a
  full dump.

## Figures

Figures are hand-drawn SVG in `figures/`, named `<objective>-<slug>.svg`.

- viewBox width 760 for wide figures, 360 for single-column figures.
- Palette only: ink `#1a1209`, muted `#5c4a30`, purple `#6d28d9`, deep purple
  `#3a1d70`, lavender `#efe6ff`, light purple `#c4b3ff`, yellow `#ffd60a`, pale
  yellow `#fffae0`, white `#fff`, rust accent `#9a3412`, rule `#d8d2c8`.
- Brand motifs: 2px ink strokes on boxes, solid offset shadows (draw a second
  ink rect offset by 2.5 units behind the box), rounded corners `rx="7"`.
- Text uses the page fonts automatically (Inter). Add `class="mono"` for
  commands. Font sizes 9 to 14 in viewBox units.
- No symbol glyphs such as check marks or arrows from fonts; draw them as
  paths. Font fallback for those glyphs embeds an ugly Type 3 font.
- Leave space: text must not touch or overflow its box. Render the page and
  look.
- Draw a figure when it shows a mechanism (flow, sequence, relationship). Do
  not draw a figure that only restates a list.

## Build and check

```sh
node scripts/build.mjs <volume>     # volumes are defined in book.json
pdftoppm -r 80 -png dist/<file>.pdf /tmp/page
```

Look at every page you produced. Check for text overflowing figures or tables,
columns left empty, a lone heading at the bottom of a column, and code lines
wrapping badly (keep code lines under 48 characters so they fit a
column).
