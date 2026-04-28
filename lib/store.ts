// ==========================================
// TaskEval v2.2 — Per-Slot Scoring + Completion Status
// ==========================================

export type UserRole = 'management' | 'candidate';
export interface User { id: string; name: string; email: string; password: string; role: UserRole; }

export type SlotStatus = 'locked' | 'working' | 'upload_open' | 'submitted' | 'missed';
export interface SlotUploads { screenshot: string | null; summary: string | null; outputLink: string | null; completionStatus: 'completed' | 'pending' | null; }
export interface TaskSlot {
  slotIndex: number; startTime: string; workEndTime: string; uploadEndTime: string; isLast: boolean;
  uploads: SlotUploads; submittedAt: string | null;
  status: SlotStatus; deductions: number; errors: string[];
}

export type TaskStatus = 'Pending' | 'In Progress' | 'Completed' | 'Issues' | 'Expired';
export interface Task {
  id: string; name: string; checklist: string[]; platform: string;
  startTime: string; endTime: string; candidate: string;
  createdBy: string; createdAt: string;
  status: TaskStatus; totalDeductions: number; score: number;
  durationMultiplier: number; pointsPerSlot: number;
  slots: TaskSlot[];
}

const USERS_KEY = 'taskeval_users'; const TASKS_KEY = 'taskeval_tasks'; const SESSION_KEY = 'taskeval_session';
const WORK_MIN = 20; const UPLOAD_MIN = 5; const BASE_HOURS = 4;

// === Users ===
export function getUsers(): User[] { if (typeof window === 'undefined') return []; const d = localStorage.getItem(USERS_KEY); return d ? JSON.parse(d) : []; }
function saveUsers(u: User[]) { localStorage.setItem(USERS_KEY, JSON.stringify(u)); }
export function signUp(name: string, email: string, password: string, role: UserRole): { success: boolean; error?: string } {
  const users = getUsers();
  if (users.find(u => u.email.toLowerCase() === email.toLowerCase())) return { success: false, error: 'Email already exists.' };
  users.push({ id: crypto.randomUUID(), name, email: email.toLowerCase(), password, role });
  saveUsers(users); return { success: true };
}
export function login(email: string, password: string): { success: boolean; user?: User; error?: string } {
  const user = getUsers().find(u => u.email.toLowerCase() === email.toLowerCase() && u.password === password);
  if (!user) return { success: false, error: 'Invalid credentials.' };
  localStorage.setItem(SESSION_KEY, JSON.stringify(user)); return { success: true, user };
}
export function getCurrentUser(): User | null {
  if (typeof window === 'undefined') return null; const d = localStorage.getItem(SESSION_KEY);
  if (!d) return null; try { const p = JSON.parse(d); if (!p?.role || !p?.email) { localStorage.removeItem(SESSION_KEY); return null; } return p; } catch { localStorage.removeItem(SESSION_KEY); return null; }
}
export function logout() { localStorage.removeItem(SESSION_KEY); }
export function getCandidateNames(): string[] { return getUsers().filter(u => u.role === 'candidate').map(u => u.name); }

// === Tasks ===
export function getTasks(): Task[] {
  if (typeof window === 'undefined') return []; const d = localStorage.getItem(TASKS_KEY);
  if (!d) return []; try { const p = JSON.parse(d);
    if (!Array.isArray(p)) { localStorage.removeItem(TASKS_KEY); return []; }
    if (p.length > 0 && (!Array.isArray(p[0].slots) || !p[0].slots?.[0]?.workEndTime || p[0].pointsPerSlot === undefined)) { localStorage.removeItem(TASKS_KEY); return []; }
    return p;
  } catch { localStorage.removeItem(TASKS_KEY); return []; }
}
function saveTasks(t: Task[]) { localStorage.setItem(TASKS_KEY, JSON.stringify(t)); }

function generateSlots(startISO: string, endISO: string): TaskSlot[] {
  const slots: TaskSlot[] = []; let current = new Date(startISO).getTime(); const end = new Date(endISO).getTime(); let idx = 0;
  while (current < end) {
    const workEnd = current + WORK_MIN * 60000;
    const uploadEnd = current + (WORK_MIN + UPLOAD_MIN) * 60000;
    const effectiveUploadEnd = Math.min(uploadEnd, end + UPLOAD_MIN * 60000);
    slots.push({ slotIndex: idx, startTime: new Date(current).toISOString(), workEndTime: new Date(workEnd).toISOString(), uploadEndTime: new Date(effectiveUploadEnd).toISOString(), isLast: false, uploads: { screenshot: null, summary: null, outputLink: null, completionStatus: null }, submittedAt: null, status: 'locked', deductions: 0, errors: [] });
    current = workEnd; idx++;
  }
  if (slots.length > 0) slots[slots.length - 1].isLast = true;
  return slots;
}

export function createTask(data: { name: string; checklist: string; platform: string; startTime: string; endTime: string; candidate: string; createdBy: string; }): Task {
  const tasks = getTasks();
  const checklistArr = data.checklist.split(',').map(s => s.trim()).filter(Boolean);
  const slots = generateSlots(data.startTime, data.endTime);
  const shiftH = (new Date(data.endTime).getTime() - new Date(data.startTime).getTime()) / 3600000;
  const durationMultiplier = parseFloat((shiftH / BASE_HOURS).toFixed(2));
  const pointsPerSlot = slots.length > 0 ? parseFloat((100 / slots.length).toFixed(2)) : 100;
  const task: Task = { id: `TASK-${String(tasks.length + 1).padStart(3, '0')}`, name: data.name, checklist: checklistArr, platform: data.platform, startTime: data.startTime, endTime: data.endTime, candidate: data.candidate, createdBy: data.createdBy, createdAt: new Date().toISOString(), status: 'Pending', totalDeductions: 0, score: 100, durationMultiplier, pointsPerSlot, slots };
  tasks.push(task); saveTasks(tasks); return task;
}

export function getTasksForCandidate(name: string): Task[] { return getTasks().filter(t => t.candidate.toLowerCase() === name.toLowerCase()); }

// === Slot Submission ===
export function submitSlot(taskId: string, slotIndex: number, screenshot: string, _name: string, summary: string, outputLink?: string, completionStatus?: 'completed' | 'pending'): Task | null {
  const tasks = getTasks(); const tIdx = tasks.findIndex(t => t.id === taskId); if (tIdx === -1) return null;
  const slot = tasks[tIdx].slots[slotIndex]; const now = Date.now();
  const uploadOpen = new Date(slot.workEndTime).getTime(); const uploadClose = new Date(slot.uploadEndTime).getTime();
  if (slot.status === 'submitted' || now < uploadOpen || now > uploadClose) return null;
  slot.uploads.screenshot = screenshot; slot.uploads.summary = summary;
  if (slot.isLast) { if (outputLink) slot.uploads.outputLink = outputLink; if (completionStatus) slot.uploads.completionStatus = completionStatus; }
  slot.submittedAt = new Date().toISOString(); slot.status = 'submitted';
  evaluateSlot(tasks[tIdx], slotIndex); recalcTask(tasks[tIdx]); saveTasks(tasks); return tasks[tIdx];
}

// === Slot State Machine ===
export function refreshSlotStates(): void {
  const tasks = getTasks(); const now = Date.now(); let changed = false;
  for (const task of tasks) { for (const slot of task.slots) {
    if (slot.status === 'submitted') continue;
    const uploadClose = new Date(slot.uploadEndTime).getTime();
    if (now > uploadClose && slot.status !== 'missed') {
      slot.status = 'missed'; slot.deductions = task.pointsPerSlot;
      slot.errors = ['Slot missed \u2014 upload window expired']; changed = true;
    }
  } if (changed) recalcTask(task); }
  if (changed) saveTasks(tasks);
}

export type LiveSlotState = 'locked' | 'working' | 'upload_open' | 'submitted' | 'missed';
export function getSlotLiveState(slot: TaskSlot): { state: LiveSlotState; remainingMs: number } {
  if (slot.status === 'submitted') return { state: 'submitted', remainingMs: 0 };
  if (slot.status === 'missed') return { state: 'missed', remainingMs: 0 };
  const now = Date.now(); const ws = new Date(slot.startTime).getTime(); const uo = new Date(slot.workEndTime).getTime(); const uc = new Date(slot.uploadEndTime).getTime();
  if (now < ws) return { state: 'locked', remainingMs: ws - now };
  if (now < uo) return { state: 'working', remainingMs: uo - now };
  if (now <= uc) return { state: 'upload_open', remainingMs: uc - now };
  return { state: 'missed', remainingMs: 0 };
}

// === Evaluation ===
function evaluateSlot(task: Task, slotIndex: number): void {
  const slot = task.slots[slotIndex]; const m = task.durationMultiplier; const cap = task.pointsPerSlot;
  const errors: string[] = []; let ded = 0;
  if (!slot.uploads.screenshot) { errors.push('Missing screenshot'); ded += 10 * m; }
  if (!slot.uploads.summary) { errors.push('Missing summary'); ded += 3 * m; }
  if (slot.isLast && !slot.uploads.outputLink) { errors.push('Missing output link'); ded += 5 * m; }
  if (slot.isLast && slot.uploads.summary) { const sL = slot.uploads.summary.toLowerCase(); for (const item of task.checklist) { if (!sL.includes(item.toLowerCase())) { errors.push(`Checklist not covered: ${item}`); ded += 2 * m; } } }
  if (slot.submittedAt) { const subT = new Date(slot.submittedAt).getTime(); const ucT = new Date(slot.uploadEndTime).getTime(); if (ucT - subT < 60000) { errors.push('Uploaded in final 60s'); ded += 2 * m; } }
  slot.errors = errors; slot.deductions = parseFloat(Math.min(ded, cap).toFixed(2));
}

function recalcTask(task: Task): void {
  const finalSlot = task.slots[task.slots.length - 1];
  if (finalSlot?.uploads?.completionStatus === 'pending') { task.status = 'Pending'; task.totalDeductions = parseFloat(task.slots.reduce((s, sl) => s + sl.deductions, 0).toFixed(2)); task.score = parseFloat(Math.max(0, 100 - task.totalDeductions).toFixed(2)); return; }
  const now = Date.now(); const started = now >= new Date(task.startTime).getTime();
  if (!started) { task.status = 'Pending'; } else {
    const allDone = task.slots.every(s => s.status === 'submitted' || s.status === 'missed');
    const anyMissed = task.slots.some(s => s.status === 'missed');
    const anyErrors = task.slots.some(s => s.errors.length > 0);
    if (!allDone) task.status = 'In Progress';
    else if (anyMissed) task.status = 'Expired';
    else if (anyErrors) task.status = 'Issues';
    else task.status = 'Completed';
  }
  task.totalDeductions = parseFloat(task.slots.reduce((s, sl) => s + sl.deductions, 0).toFixed(2));
  task.score = parseFloat(Math.max(0, 100 - task.totalDeductions).toFixed(2));
}

// === Filter/Sort (Management) ===
export interface FilterState { candidate: string; platform: string; status: string; sort: string; }
export function getFilteredTasks(tasks: Task[], f: FilterState): Task[] {
  let r = [...tasks];
  if (f.candidate.trim()) r = r.filter(t => t.candidate.toLowerCase().includes(f.candidate.toLowerCase()));
  if (f.platform && f.platform !== 'all') r = r.filter(t => t.platform === f.platform);
  if (f.status && f.status !== 'all') r = r.filter(t => t.status === f.status);
  const sortMap: Record<string, (a: Task, b: Task) => number> = {
    newest: (a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime(),
    oldest: (a, b) => new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime(),
    'deadline-asc': (a, b) => new Date(a.endTime).getTime() - new Date(b.endTime).getTime(),
    'deadline-desc': (a, b) => new Date(b.endTime).getTime() - new Date(a.endTime).getTime(),
    'score-high': (a, b) => b.score - a.score, 'score-low': (a, b) => a.score - b.score,
    'candidate-az': (a, b) => a.candidate.localeCompare(b.candidate), 'candidate-za': (a, b) => b.candidate.localeCompare(a.candidate),
  };
  if (sortMap[f.sort]) r.sort(sortMap[f.sort]);
  return r;
}

// === Utilities ===
export function formatDT(iso: string | null): string { if (!iso) return '\u2014'; const d = new Date(iso); return d.toLocaleDateString('en-GB', { day: '2-digit', month: '2-digit', year: 'numeric' }) + ' ' + d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }); }
export function formatTime(iso: string): string { return new Date(iso).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }); }
export function formatCountdown(ms: number): string { if (ms <= 0) return '00:00'; const ts = Math.floor(ms / 1000); const h = Math.floor(ts / 3600); const m = Math.floor((ts % 3600) / 60); const s = ts % 60; if (h > 0) return `${h}h ${String(m).padStart(2, '0')}m`; return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`; }

