# Kanban Sticky

A floating Kanban widget for macOS with Todo, Progress, and Done columns.

## Run

Run:

```sh
./build-and-run.sh
```

Tasks are stored on macOS using UserDefaults. Hover over a task to reveal its actions. Click the circle on the left to mark it complete.

Drag an edge or corner to resize the widget. At about 720 px wide, it switches to a three-column board. In this layout, drag tasks between Todo, Progress, and Done.

The widget restores its last size and position when it opens.

`Command + W` hides the widget. Launch `~/Applications/Kanban Sticky.app` to show it again.

The More menu switches between English and Bahasa Indonesia. English is the default.

## Menu bar

The checklist icon in the menu bar can show or hide the widget, open a new task form for a status, display task counts, or quit the app.

Kanban Sticky creates a Login Agent on first launch so it opens when you log in to macOS.

## Create the installer

Run `./create-installer.sh` to create a DMG in `dist`. The DMG contains the app and a shortcut to the Applications folder.

## Preview

![Transparent compact theme with desktop background](docs/kanban-sticky-transparent-desktop-compact.png)

![Transparent wide theme with desktop background](docs/kanban-sticky-transparent-desktop.png)

[View the sample walkthrough video](docs/kanban-sticky-walkthrough-sample-crop.mov)
