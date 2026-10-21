# RHCSA EX200 Course Notes

Open course notes for the Red Hat Certified System Administrator exam
(EX200, RHEL 10), written by Dr. Frazier A. Smith of Central Piedmont
Community College and published for anyone studying for the exam. Styled
with the [vfrazier.app](https://vfrazier.app) brand, and built with the same
toolchain as the [AutoOps+](https://github.com/frazier-at-cpcc/autoops-course-notes)
and [SecAI+](https://github.com/frazier-at-cpcc/secai-course-notes) notes.

The notes follow Red Hat's ten objective groups in order. Each topic is a
Markdown file, and the build turns them into a two-column, print-ready PDF
with a cover, contents, group dividers, figures, and PDF bookmarks.

## Status

Work in progress on the `build/1.0-notes` branch.

See [AUTHORING.md](AUTHORING.md) for how topics are written and tested.

## Every command was run

Each command and output shown in the notes comes from a real run on RHEL 10
or its rebuild AlmaLinux 10. Two kits produce that output:

- `tests/` holds a script per container-friendly topic (shell, text,
  archives, permissions, users, scripting, dnf). Each starts an AlmaLinux 10
  container with `tests/lib/container.sh`, reruns the commands, and checks
  the output. Run them locally with Docker, or start the **Command tests**
  workflow from the Actions tab.
- `lab/` captures the topics that need a whole system: disks and LVM,
  systemd, the journal, NetworkManager, firewalld, SELinux, and the boot
  loader. `sudo lab/run.sh` runs on a disposable RHEL 10 VM with two spare
  disks and a spare NIC, reboots it to prove each change persists, and
  writes the sessions to `lab/results/`. See [lab/README.md](lab/README.md).

```sh
npm install
npm run build                              # writes all PDFs to dist/
bash tests/1.5-archives.sh                 # one container topic
sudo lab/run.sh 5.2                        # one full-system topic, on the lab VM
```

## Writing a topic

Add a file under `content/domain-N/` and list it in `book.json` under the
`master` volume. The per-domain volumes pick up their topics from that list.

```markdown
---
objective: 5.2
title: Logical Volume Management
---

### A subheading
- A bullet with a ==must-know term== in the yellow highlighter
  - A sub-bullet

:::figure wide my-diagram.svg | Caption text
:::exam
How this shows up on the exam.
:::
:::try Optional custom label
A short hands-on exercise.
:::
:::wide
| A table | that spans | both columns |
|---|---|---|
:::
```

Code fences take a label: ` ```console label="Terminal" `. In `console`
blocks, lines starting with `$ ` are commands and everything else is output.

Figures are hand-drawn SVGs in `figures/` using the brand palette. The exam
name, code, cover text, and exam facts come from the `exam` block in
`book.json`, so the build scripts carry no exam-specific text.

## Brand

`styles/tokens.css` is copied verbatim from the vfrazier.app site repo, so
colors match the site exactly. Run `scripts/sync-tokens.sh` after changing the
site's palette. Type is Inter with IBM Plex Mono for code, both self-hosted.

## Releases

Every push and pull request builds the PDFs (download them from the run's
`course-notes-pdf` artifact). Push a tag such as `v1.0.0` and the build attaches
the PDFs to a GitHub release.

## License

Text and figures: [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).
Build scripts and tests: MIT.

Red Hat, Red Hat Enterprise Linux, and RHCSA are trademarks of Red Hat, Inc.
This project is not affiliated with or endorsed by Red Hat.
