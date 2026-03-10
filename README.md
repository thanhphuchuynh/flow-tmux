# flow-tmux

A Pomodoro focus timer that lives in your tmux status bar. Work/break intervals, pause/resume, session goals, Kanban tasks, notifications, and stats — no background daemon. All advanced features are opt-in (disabled by default).

## Install

**With TPM:**
```bash
set -g @plugin 'user/flow-tmux'
```

**Manual:**
```bash
git clone https://github.com/thanhphuchuynh/flow-tmux ~/.tmux/plugins/flow-tmux
# Add to .tmux.conf:
run '~/.tmux/plugins/flow-tmux/flow-tmux.tmux'
```

Then add `#{flow_status}` to your status bar:
```bash
set -g status-right '#{flow_status} | %H:%M %d-%b'
```

> **Rose Pine users** — use the prepend option instead:
> ```bash
> set -g @rose_pine_status_right_prepend_section '#(~/.tmux/plugins/flow-tmux/scripts/status.sh) '
> ```

Set `status-interval` to 1 second for real-time countdown:
```bash
set -g status-interval 1
```

Reload: `tmux source ~/.tmux.conf`

## Keybindings

| Key | Action |
|-----|--------|
| `prefix + F` | Start (with goal prompt) / Pause / Resume |
| `prefix + Ctrl+f` | Cancel timer |
| `prefix + Alt+f` | Open flow menu |
| `prefix + T` | Open task board menu |
| `prefix + D` | Log distraction (when `@flow_distraction on`) |

## Status Bar

| State | Display |
|-------|---------|
| Idle | *(empty)* |
| Working | `󱎫 24:32 󰀘 fix auth bug` |
| Break | `󰅶 04:15` |
| Paused | `󰏤 18:03 󰀘 fix auth bug` |

With optional features enabled:
```
󱎫 18:32 ████░░░░ 󰀘 fix auth bug 4/8 󰈸3d
│        │         │               │    └─ streak (3 days)
│        │         │               └─ daily goal (4 of 8)
│        │         └─ current goal
│        └─ progress bar
└─ timer
```

## Features

### Core (always on)
- Timer with work/break/long-break intervals
- Pause/resume, skip, cancel
- Session goals (prompted on start)
- Kanban task board (Todo / In Progress / Done)
- OS notifications + terminal bell
- Session stats

### Optional Features

All disabled by default. Enable in `.tmux.conf`:

#### Productivity
| Option | Description |
|--------|-------------|
| `@flow_auto_start on` | Auto-start work after break ends (no manual `prefix+F`) |
| `@flow_daily_goal 8` | Set daily target, shows `4/8` progress in status bar |
| `@flow_streak on` | Show consecutive day streak `󰈸3d` in status bar |
| `@flow_distraction on` | Enable distraction logging hotkey (`prefix+D`) |

#### Better UX
| Option | Description |
|--------|-------------|
| `@flow_colors on` | Color-coded status: red=work, green=break, yellow=paused |
| `@flow_progress_bar on` | Visual progress `████░░░░` in status bar |
| `@flow_tick on` | Subtle tick sound every minute during last 5 min (macOS) |
| `@flow_format '{icon} {bar} {time} {goal}'` | Custom status format template |

Format placeholders: `{icon}`, `{time}`, `{goal}`, `{bar}`, `{daily}`, `{streak}`

#### Task Management
| Option | Description |
|--------|-------------|
| `@flow_task_priority on` | Task priority: prefix with `!` (high) or `~` (low) |
| `@flow_task_tracking on` | Track pomodoro count per task, show `[3x]` on board |
| `@flow_subtasks on` | Break tasks into subtasks, check off from menu |
| `@flow_recurring on` | Add `@daily` suffix to auto-reset tasks each day |

#### Data & Insights
| Option | Description |
|--------|-------------|
| `@flow_weekly_report on` | Weekly report popup in menu (7-day breakdown) |
| `@flow_heatmap on` | GitHub-style heatmap popup (4 weeks) |
| `@flow_export on` | Export stats to JSON or Markdown |

#### Session
| Option | Description |
|--------|-------------|
| `@flow_session_aware on` | Independent timer per tmux session |

## Task Board

Press `prefix + T`:

```
󰐃 Tasks
─────────────
  󰃨 View Board       b
  󰐕 Add Task          a
  󰀘 Pick & Focus     f

  󰄬 Complete Current  d
  󰆴 Delete Task      x

  󰐕 Add Subtask       s    (when @flow_subtasks on)
  󰄬 Complete Subtask  S    (when @flow_subtasks on)
```

### Adding tasks with priority & recurring

When `@flow_task_priority on`:
```
!fix critical bug      → high priority
~update readme         → low priority
deploy to staging      → normal priority
```

When `@flow_recurring on`:
```
standup meeting @daily → resets to Todo each morning
```

### Board view

```
━━━ 󰈸 IN PROGRESS ━━━
  ! #3 fix auth bug [2x] 󰑖
    󰄬 add validation
      check edge cases

━━━ 󰃨 TODO ━━━
  ! #1 write API tests
  - #2 update docs
  ~ #5 refactor utils

━━━ 󰄬 DONE ━━━
  - #4 setup CI pipeline [3x]
```

## Distraction Log

When `@flow_distraction on`, press `prefix + D` during a focus session:

```
󰍉 Distraction: _
```

View today's distractions from the flow menu (`prefix + Alt+f` → `V`):

```
━━━ 󰍉 Today's Distractions ━━━

  09:32 [work] Slack notification from team
  10:15 [work] Checked Twitter
  11:42 [work] Phone call

━━━ Total: 3 ━━━
```

## Stats & Reports

### Basic stats
From menu (`v`) or:
```bash
~/.tmux/plugins/flow-tmux/scripts/stats.sh show
```
```
󰄧 Today: 6 sessions (2h30m) | Total: 42 sessions (17h30m) | 󰈸 5d streak
```

### Weekly report (`@flow_weekly_report on`)
```
━━━ 󰄧 Weekly Report ━━━

  Thu 2026-03-05  ██████░░░░░░  6 (2h30m)
  Wed 2026-03-04  ████████░░░░  8 (3h20m)
  Tue 2026-03-03  ████░░░░░░░░  4 (1h40m)
  ...

  Most productive hour: 10:00 (12 sessions)
  Current streak: 󰈸 5 days
```

### Heatmap (`@flow_heatmap on`)
```
━━━ 󰄧 Focus Heatmap (4 weeks) ━━━

         Mon Tue Wed Thu Fri Sat Sun
  W-3    ░   ▒   ▓   ░   █   ░   ░
  W-2    ▓   ░   ▒   ▓   ░   ▒   ░
  W-1    █   ▒   ▓   █   ▒   ░   ░
  This   ▓   █   ▓   ▒

  ░ = 0  ▒ = 1-2  ▓ = 3-5  █ = 6+
```

### Export (`@flow_export on`)
```bash
stats.sh export json   # → ~/.cache/flow-tmux/export.json
stats.sh export md     # → ~/.cache/flow-tmux/export.md
```

## Full Configuration Reference

```bash
# Core
set -g @flow_work_duration '25'
set -g @flow_break_duration '5'
set -g @flow_long_break_duration '15'
set -g @flow_long_break_after '4'

# Notifications
set -g @flow_notify 'on'
set -g @flow_bell 'on'
set -g @flow_sound 'Glass'

# Keybindings
set -g @flow_toggle_key 'F'
set -g @flow_cancel_key 'C-f'
set -g @flow_menu_key 'M-f'
set -g @flow_tasks_key 'T'
set -g @flow_distraction_key 'D'

# Productivity (default: off)
set -g @flow_auto_start 'off'
set -g @flow_daily_goal '0'            # 0=disabled, N=target sessions
set -g @flow_streak 'off'
set -g @flow_distraction 'off'

# UX (default: off)
set -g @flow_colors 'off'
set -g @flow_progress_bar 'off'
set -g @flow_tick 'off'
set -g @flow_format ''                  # custom format template

# Task features (default: off)
set -g @flow_task_priority 'off'
set -g @flow_task_tracking 'off'
set -g @flow_subtasks 'off'
set -g @flow_recurring 'off'

# Data (default: off)
set -g @flow_weekly_report 'off'
set -g @flow_heatmap 'off'
set -g @flow_export 'off'

# Session (default: off)
set -g @flow_session_aware 'off'
```

## Full .tmux.conf Example

```bash
set -g status-interval 1

set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'user/flow-tmux'

# Core
set -g @flow_work_duration '25'
set -g @flow_break_duration '5'

# Enable features you want
set -g @flow_colors 'on'
set -g @flow_progress_bar 'on'
set -g @flow_daily_goal '8'
set -g @flow_streak 'on'
set -g @flow_distraction 'on'
set -g @flow_task_priority 'on'
set -g @flow_task_tracking 'on'
set -g @flow_weekly_report 'on'
set -g @flow_heatmap 'on'

set -g status-right '#{flow_status} | %H:%M %d-%b'
run '~/.tmux/plugins/tpm/tpm'
```

## How It Works

- **No background process** — state computed on each `status-interval` tick
- **State files** in `/tmp/flow_tmux/` (cleared on reboot)
- **Tasks & stats** in `~/.cache/flow-tmux/` (persists across reboots)
- Auto-cycles: work → break → work with long break every N sessions
- Session-aware mode uses `/tmp/flow_tmux/<session_name>/` for independent timers
