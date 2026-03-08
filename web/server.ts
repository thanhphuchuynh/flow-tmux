import { readFileSync, writeFileSync, existsSync } from "fs";
import { join } from "path";

const STATS_DIR = join(process.env.HOME!, ".cache/flow-tmux");
const STATE_DIR = process.env.FLOW_STATE_DIR || "/tmp/flow_tmux";
const PORT = parseInt(process.env.FLOW_PORT || "3777");
const TASKS_FILE = join(STATS_DIR, "tasks.tsv");
const SUBTASKS_FILE = join(STATS_DIR, "subtasks.tsv");
const PROJECTS_FILE = join(STATS_DIR, "projects.conf");
const NOTIFICATIONS_FILE = join(STATS_DIR, "notifications.csv");

// ── Readers ──

function readCSV(path: string): string[][] {
  if (!existsSync(path)) return [];
  return readFileSync(path, "utf-8")
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((line) => line.split(","));
}

function readState(key: string, fallback = ""): string {
  const file = join(STATE_DIR, key);
  return existsSync(file) ? readFileSync(file, "utf-8").trim() : fallback;
}

interface Task {
  id: number;
  status: string;
  title: string;
  created: string;
  priority: string;
  pomodoros: number;
  recurring: string;
}

function readTasks(): Task[] {
  if (!existsSync(TASKS_FILE)) return [];
  return readFileSync(TASKS_FILE, "utf-8")
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((line) => {
      const [id, status, title, created, priority, pomodoros, recurring] =
        line.split("\t");
      return {
        id: parseInt(id),
        status,
        title,
        created,
        priority: priority || "-",
        pomodoros: parseInt(pomodoros || "0"),
        recurring: recurring || "",
      };
    });
}

function writeTasks(tasks: Task[]) {
  const lines = tasks.map(
    (t) =>
      `${t.id}\t${t.status}\t${t.title}\t${t.created}\t${t.priority}\t${t.pomodoros}\t${t.recurring}`
  );
  writeFileSync(TASKS_FILE, lines.join("\n") + "\n");
}

function readSubtasks(): {
  parentId: number;
  subId: number;
  status: string;
  title: string;
}[] {
  if (!existsSync(SUBTASKS_FILE)) return [];
  return readFileSync(SUBTASKS_FILE, "utf-8")
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((line) => {
      const [parentId, subId, status, title] = line.split("\t");
      return {
        parentId: parseInt(parentId),
        subId: parseInt(subId),
        status,
        title,
      };
    });
}

function writeSubtasks(
  subs: { parentId: number; subId: number; status: string; title: string }[]
) {
  const lines = subs.map(
    (s) => `${s.parentId}\t${s.subId}\t${s.status}\t${s.title}`
  );
  writeFileSync(SUBTASKS_FILE, lines.join("\n") + (lines.length ? "\n" : ""));
}

// ── Stats ──

function getStats() {
  const rows = readCSV(join(STATS_DIR, "stats.csv"));
  const today = new Date().toISOString().slice(0, 10);
  const sessions = rows.map(([timestamp, duration, type, goal]) => ({
    timestamp,
    duration: parseInt(duration),
    type,
    goal: goal || "",
  }));
  const todaySessions = sessions.filter(
    (s) => s.type === "work" && s.timestamp.startsWith(today)
  );
  const totalWork = sessions.filter((s) => s.type === "work");

  const dailyMap: Record<string, { count: number; minutes: number }> = {};
  for (let i = 0; i < 14; i++) {
    const d = new Date();
    d.setDate(d.getDate() - i);
    const key = d.toISOString().slice(0, 10);
    dailyMap[key] = { count: 0, minutes: 0 };
  }
  for (const s of totalWork) {
    const day = s.timestamp.slice(0, 10);
    if (dailyMap[day]) {
      dailyMap[day].count++;
      dailyMap[day].minutes += s.duration;
    }
  }

  const hourly = new Array(24).fill(0);
  for (const s of totalWork) {
    const hour = parseInt(s.timestamp.split("T")[1]?.split(":")[0] || "0");
    hourly[hour]++;
  }

  let streak = 0;
  const checkDate = new Date();
  const workDays = new Set(totalWork.map((s) => s.timestamp.slice(0, 10)));
  while (workDays.has(checkDate.toISOString().slice(0, 10))) {
    streak++;
    checkDate.setDate(checkDate.getDate() - 1);
  }

  const heatmap: { date: string; count: number }[] = [];
  for (let i = 27; i >= 0; i--) {
    const d = new Date();
    d.setDate(d.getDate() - i);
    const key = d.toISOString().slice(0, 10);
    const count = totalWork.filter((s) => s.timestamp.startsWith(key)).length;
    heatmap.push({ date: key, count });
  }

  return {
    today: {
      count: todaySessions.length,
      minutes: todaySessions.reduce((a, s) => a + s.duration, 0),
    },
    total: {
      count: totalWork.length,
      minutes: totalWork.reduce((a, s) => a + s.duration, 0),
    },
    streak,
    daily: Object.entries(dailyMap)
      .sort()
      .map(([date, data]) => ({ date, ...data })),
    hourly,
    heatmap,
    recentSessions: sessions.slice(-20).reverse(),
  };
}

function getDistractions() {
  const rows = readCSV(join(STATS_DIR, "distractions.csv"));
  return rows.map(([timestamp, phase, ...msgParts]) => ({
    timestamp,
    phase,
    message: msgParts.join(","),
  }));
}

function getTimerState() {
  return {
    status: readState("status", "idle"),
    goal: readState("goal"),
    startTime: parseInt(readState("start_time", "0")),
    timePaused: parseInt(readState("time_paused", "0")),
    pausedAt: readState("paused_at")
      ? parseInt(readState("paused_at"))
      : null,
    phaseBefore: readState("phase_before_pause") || null,
    sessionCount: parseInt(readState("session_count", "0")),
    currentTaskId: readState("current_task_id") || null,
  };
}

// ── Task CRUD ──

function addTask(body: {
  title: string;
  priority?: string;
  recurring?: string;
}): Task {
  const tasks = readTasks();
  const maxId = tasks.reduce((m, t) => Math.max(m, t.id), 0);
  const task: Task = {
    id: maxId + 1,
    status: "todo",
    title: body.title,
    created: new Date().toISOString().replace(/\.\d+Z$/, ""),
    priority: body.priority || "-",
    pomodoros: 0,
    recurring: body.recurring || "",
  };
  tasks.push(task);
  writeTasks(tasks);
  return task;
}

function updateTask(
  id: number,
  updates: Partial<
    Pick<Task, "title" | "status" | "priority" | "recurring" | "pomodoros">
  >
): Task | null {
  const tasks = readTasks();
  const idx = tasks.findIndex((t) => t.id === id);
  if (idx === -1) return null;
  if (updates.title !== undefined) tasks[idx].title = updates.title;
  if (updates.status !== undefined) tasks[idx].status = updates.status;
  if (updates.priority !== undefined) tasks[idx].priority = updates.priority;
  if (updates.recurring !== undefined) tasks[idx].recurring = updates.recurring;
  if (updates.pomodoros !== undefined) tasks[idx].pomodoros = updates.pomodoros;
  writeTasks(tasks);
  return tasks[idx];
}

function deleteTask(id: number): boolean {
  const tasks = readTasks();
  const filtered = tasks.filter((t) => t.id !== id);
  if (filtered.length === tasks.length) return false;
  writeTasks(filtered);
  // Also remove subtasks
  const subs = readSubtasks().filter((s) => s.parentId !== id);
  writeSubtasks(subs);
  return true;
}

// ── Subtask CRUD ──

function addSubtask(parentId: number, title: string) {
  const subs = readSubtasks();
  const maxSid = subs
    .filter((s) => s.parentId === parentId)
    .reduce((m, s) => Math.max(m, s.subId), 0);
  const sub = { parentId, subId: maxSid + 1, status: "todo", title };
  subs.push(sub);
  writeSubtasks(subs);
  return sub;
}

function updateSubtask(parentId: number, subId: number, status: string) {
  const subs = readSubtasks();
  const s = subs.find((s) => s.parentId === parentId && s.subId === subId);
  if (!s) return null;
  s.status = status;
  writeSubtasks(subs);
  return s;
}

function deleteSubtask(parentId: number, subId: number) {
  const subs = readSubtasks();
  const filtered = subs.filter(
    (s) => !(s.parentId === parentId && s.subId === subId)
  );
  writeSubtasks(filtered);
  return filtered.length < subs.length;
}

// ── Projects ──

interface Project {
  name: string;
  windows: { name: string; dir: string; cmd: string }[];
}

function readProjects(): Project[] {
  if (!existsSync(PROJECTS_FILE)) return [];
  const lines = readFileSync(PROJECTS_FILE, "utf-8").split("\n");
  const projects: Project[] = [];
  let current: Project | null = null;
  for (const line of lines) {
    if (!line.trim() || line.startsWith("#")) continue;
    if (line.startsWith("project:")) {
      current = { name: line.slice(8), windows: [] };
      projects.push(current);
    } else if (line.startsWith("window:") && current) {
      const [name, dir, cmd] = line.slice(7).split("|");
      current.windows.push({ name: name || "", dir: dir || "", cmd: cmd || "" });
    }
  }
  return projects;
}

// ── Notifications ──

function readNotifications(): { timestamp: string; type: string; message: string }[] {
  if (!existsSync(NOTIFICATIONS_FILE)) return [];
  return readFileSync(NOTIFICATIONS_FILE, "utf-8")
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((line) => {
      const [timestamp, type, ...msgParts] = line.split(",");
      return { timestamp, type, message: msgParts.join(",") };
    });
}

function clearNotifications() {
  if (existsSync(NOTIFICATIONS_FILE)) {
    writeFileSync(NOTIFICATIONS_FILE, "");
  }
}

// ── Server ──

const HTML_PATH = join(import.meta.dir, "dashboard.html");

Bun.serve({
  port: PORT,
  async fetch(req) {
    const url = new URL(req.url);
    const method = req.method;

    const jsonHeaders = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
      "Content-Type": "application/json",
    };

    if (method === "OPTIONS") {
      return new Response(null, { status: 204, headers: jsonHeaders });
    }

    const path = url.pathname;
    const taskMatch = path.match(/^\/api\/tasks\/(\d+)$/);
    const subMatch = path.match(/^\/api\/tasks\/(\d+)\/subtasks$/);
    const subItemMatch = path.match(/^\/api\/tasks\/(\d+)\/subtasks\/(\d+)$/);

    // ── HTML ──
    if (method === "GET" && path === "/") {
      return new Response(readFileSync(HTML_PATH, "utf-8"), {
        headers: { "Content-Type": "text/html" },
      });
    }

    // ── GET ──
    if (method === "GET") {
      if (path === "/api/stats")
        return Response.json(getStats(), { headers: jsonHeaders });
      if (path === "/api/tasks")
        return Response.json({ tasks: readTasks(), subtasks: readSubtasks() }, { headers: jsonHeaders });
      if (path === "/api/distractions")
        return Response.json(getDistractions(), { headers: jsonHeaders });
      if (path === "/api/timer")
        return Response.json(getTimerState(), { headers: jsonHeaders });
      if (path === "/api/projects")
        return Response.json(readProjects(), { headers: jsonHeaders });
      if (path === "/api/notifications")
        return Response.json(readNotifications(), { headers: jsonHeaders });
      if (path === "/api/all")
        return Response.json({
          timer: getTimerState(), stats: getStats(),
          tasks: readTasks(), subtasks: readSubtasks(),
          distractions: getDistractions(),
          projects: readProjects(),
          notifications: readNotifications(),
        }, { headers: jsonHeaders });
    }

    // ── Parse JSON body for write methods ──
    let body: any = null;
    if (method === "POST" || method === "PUT") {
      try {
        const text = await req.text();
        body = JSON.parse(text);
      } catch {
        return Response.json({ error: "Invalid JSON" }, { status: 400, headers: jsonHeaders });
      }
    }

    // ── POST ──
    if (method === "POST") {
      if (path === "/api/tasks") {
        return Response.json(addTask(body), { status: 201, headers: jsonHeaders });
      }
      if (subMatch) {
        return Response.json(addSubtask(parseInt(subMatch[1]), body.title), { status: 201, headers: jsonHeaders });
      }
    }

    // ── PUT ──
    if (method === "PUT") {
      if (taskMatch) {
        const task = updateTask(parseInt(taskMatch[1]), body);
        if (!task) return Response.json({ error: "Not found" }, { status: 404, headers: jsonHeaders });
        return Response.json(task, { headers: jsonHeaders });
      }
      if (subItemMatch) {
        const sub = updateSubtask(parseInt(subItemMatch[1]), parseInt(subItemMatch[2]), body.status);
        if (!sub) return Response.json({ error: "Not found" }, { status: 404, headers: jsonHeaders });
        return Response.json(sub, { headers: jsonHeaders });
      }
    }

    // ── DELETE ──
    if (method === "DELETE") {
      if (taskMatch) {
        const ok = deleteTask(parseInt(taskMatch[1]));
        if (!ok) return Response.json({ error: "Not found" }, { status: 404, headers: jsonHeaders });
        return Response.json({ ok: true }, { headers: jsonHeaders });
      }
      if (subItemMatch) {
        deleteSubtask(parseInt(subItemMatch[1]), parseInt(subItemMatch[2]));
        return Response.json({ ok: true }, { headers: jsonHeaders });
      }
      if (path === "/api/notifications") {
        clearNotifications();
        return Response.json({ ok: true }, { headers: jsonHeaders });
      }
    }

    return new Response("Not Found", { status: 404 });
  },
});

console.log(`󱎫 flow-tmux dashboard running at http://localhost:${PORT}`);
console.log(`  Access from phone: http://${getLocalIP()}:${PORT}`);

function getLocalIP(): string {
  const { networkInterfaces } = require("os");
  const nets = networkInterfaces();
  for (const name of Object.keys(nets)) {
    for (const net of nets[name]!) {
      if (net.family === "IPv4" && !net.internal) return net.address;
    }
  }
  return "localhost";
}
