#!/bin/bash
# TaskEval v2.2 — Auto-setup script
# Run this inside your empty git repo: bash setup.sh

echo "Setting up TaskEval..."

mkdir -p lib
cat > 'lib/store.ts' << 'ENDOFFILE'
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

ENDOFFILE

mkdir -p app
cat > 'app/page.tsx' << 'ENDOFFILE'
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { login, signUp, UserRole } from "@/lib/store";
import { motion, AnimatePresence } from "framer-motion";
import { Shield, UserCheck, LogIn, UserPlus, Mail, Lock, User, AlertCircle } from "lucide-react";

export default function AuthPage() {
  const router = useRouter();
  const [mode, setMode] = useState<"login" | "signup">("login");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [role, setRole] = useState<UserRole>("candidate");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setLoading(true);

    await new Promise((r) => setTimeout(r, 400));

    if (mode === "signup") {
      if (!name.trim()) {
        setError("Name is required.");
        setLoading(false);
        return;
      }
      const result = signUp(name.trim(), email.trim(), password, role);
      if (!result.success) {
        setError(result.error || "Signup failed.");
        setLoading(false);
        return;
      }
      const loginResult = login(email.trim(), password);
      if (loginResult.success && loginResult.user) {
        router.push(loginResult.user.role === "management" ? "/management" : "/candidate");
        return;
      }
    } else {
      const result = login(email.trim(), password);
      if (!result.success) {
        setError(result.error || "Login failed.");
        setLoading(false);
        return;
      }
      if (result.user) {
        router.push(result.user.role === "management" ? "/management" : "/candidate");
        return;
      }
    }
    setLoading(false);
  };

  return (
    <div className="min-h-screen flex items-center justify-center px-4" style={{ background: "linear-gradient(135deg, #06060a 0%, #0d0d15 50%, #0a0a14 100%)" }}>
      {/* Subtle grid overlay */}
      <div className="fixed inset-0 opacity-[0.03]" style={{ backgroundImage: "linear-gradient(rgba(255,255,255,0.1) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.1) 1px, transparent 1px)", backgroundSize: "64px 64px" }} />

      <motion.div
        initial={{ opacity: 0, y: 24 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="relative w-full max-w-md"
      >
        {/* Logo / Brand */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-14 h-14 rounded-2xl bg-primary/10 border border-primary/20 mb-4">
            <Shield className="w-7 h-7 text-primary" />
          </div>
          <h1 className="text-2xl font-bold text-foreground tracking-tight">TaskEval</h1>
          <p className="text-muted-foreground text-sm mt-1">Task Management & Evaluation System</p>
        </div>

        {/* Card */}
        <div className="rounded-2xl border border-border/60 bg-card/80 backdrop-blur-sm p-6 shadow-2xl shadow-black/40">
          {/* Mode Toggle */}
          <div className="flex rounded-xl bg-muted/50 p-1 mb-6">
            <button
              onClick={() => { setMode("login"); setError(""); }}
              className={`flex-1 flex items-center justify-center gap-2 py-2.5 rounded-lg text-sm font-medium transition-all duration-200 ${
                mode === "login"
                  ? "bg-primary text-primary-foreground shadow-lg shadow-primary/25"
                  : "text-muted-foreground hover:text-foreground"
              }`}
            >
              <LogIn className="w-4 h-4" />
              Sign In
            </button>
            <button
              onClick={() => { setMode("signup"); setError(""); }}
              className={`flex-1 flex items-center justify-center gap-2 py-2.5 rounded-lg text-sm font-medium transition-all duration-200 ${
                mode === "signup"
                  ? "bg-primary text-primary-foreground shadow-lg shadow-primary/25"
                  : "text-muted-foreground hover:text-foreground"
              }`}
            >
              <UserPlus className="w-4 h-4" />
              Sign Up
            </button>
          </div>

          <AnimatePresence mode="wait">
            {error && (
              <motion.div
                initial={{ opacity: 0, height: 0 }}
                animate={{ opacity: 1, height: "auto" }}
                exit={{ opacity: 0, height: 0 }}
                className="flex items-center gap-2 text-destructive text-sm bg-destructive/10 border border-destructive/20 rounded-lg px-3 py-2.5 mb-4"
              >
                <AlertCircle className="w-4 h-4 shrink-0" />
                {error}
              </motion.div>
            )}
          </AnimatePresence>

          <form onSubmit={handleSubmit} className="space-y-4">
            <AnimatePresence mode="wait">
              {mode === "signup" && (
                <motion.div
                  key="name"
                  initial={{ opacity: 0, height: 0 }}
                  animate={{ opacity: 1, height: "auto" }}
                  exit={{ opacity: 0, height: 0 }}
                >
                  <label className="block text-xs font-medium text-muted-foreground uppercase tracking-wider mb-1.5">Full Name</label>
                  <div className="relative">
                    <User className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                    <input
                      type="text"
                      value={name}
                      onChange={(e) => setName(e.target.value)}
                      placeholder="John Doe"
                      className="w-full pl-10 pr-4 py-2.5 rounded-lg bg-muted/50 border border-border/60 text-foreground placeholder-muted-foreground/50 focus:outline-none focus:ring-2 focus:ring-primary/40 focus:border-primary/40 text-sm transition-all"
                    />
                  </div>
                </motion.div>
              )}
            </AnimatePresence>

            <div>
              <label className="block text-xs font-medium text-muted-foreground uppercase tracking-wider mb-1.5">Email</label>
              <div className="relative">
                <Mail className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="you@example.com"
                  required
                  className="w-full pl-10 pr-4 py-2.5 rounded-lg bg-muted/50 border border-border/60 text-foreground placeholder-muted-foreground/50 focus:outline-none focus:ring-2 focus:ring-primary/40 focus:border-primary/40 text-sm transition-all"
                />
              </div>
            </div>

            <div>
              <label className="block text-xs font-medium text-muted-foreground uppercase tracking-wider mb-1.5">Password</label>
              <div className="relative">
                <Lock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                <input
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="Enter password"
                  required
                  minLength={3}
                  className="w-full pl-10 pr-4 py-2.5 rounded-lg bg-muted/50 border border-border/60 text-foreground placeholder-muted-foreground/50 focus:outline-none focus:ring-2 focus:ring-primary/40 focus:border-primary/40 text-sm transition-all"
                />
              </div>
            </div>

            <AnimatePresence mode="wait">
              {mode === "signup" && (
                <motion.div
                  key="role"
                  initial={{ opacity: 0, height: 0 }}
                  animate={{ opacity: 1, height: "auto" }}
                  exit={{ opacity: 0, height: 0 }}
                >
                  <label className="block text-xs font-medium text-muted-foreground uppercase tracking-wider mb-1.5">Role</label>
                  <div className="grid grid-cols-2 gap-3">
                    <button
                      type="button"
                      onClick={() => setRole("management")}
                      className={`flex items-center gap-2 p-3 rounded-lg border text-sm font-medium transition-all duration-200 ${
                        role === "management"
                          ? "border-accent bg-accent/10 text-accent"
                          : "border-border/60 bg-muted/30 text-muted-foreground hover:border-border"
                      }`}
                    >
                      <Shield className="w-4 h-4" />
                      Management
                    </button>
                    <button
                      type="button"
                      onClick={() => setRole("candidate")}
                      className={`flex items-center gap-2 p-3 rounded-lg border text-sm font-medium transition-all duration-200 ${
                        role === "candidate"
                          ? "border-primary bg-primary/10 text-primary"
                          : "border-border/60 bg-muted/30 text-muted-foreground hover:border-border"
                      }`}
                    >
                      <UserCheck className="w-4 h-4" />
                      Candidate
                    </button>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>

            <button
              type="submit"
              disabled={loading}
              className="w-full py-2.5 rounded-lg bg-primary text-primary-foreground font-semibold text-sm hover:bg-primary/90 transition-all duration-200 shadow-lg shadow-primary/20 disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2 mt-2"
            >
              {loading ? (
                <div className="w-4 h-4 border-2 border-primary-foreground/30 border-t-primary-foreground rounded-full animate-spin" />
              ) : mode === "login" ? (
                <><LogIn className="w-4 h-4" /> Sign In</>
              ) : (
                <><UserPlus className="w-4 h-4" /> Create Account</>
              )}
            </button>
          </form>
        </div>

        <p className="text-center text-muted-foreground/40 text-xs mt-6">TaskEval v1.0 — Prototype</p>
      </motion.div>
    </div>
  );
}



ENDOFFILE

mkdir -p app
cat > 'app/globals.css' << 'ENDOFFILE'
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap');
@import "tailwindcss";

:root {
  --background: 228 15% 4%;
  --foreground: 210 40% 96%;
  --card: 228 12% 8%;
  --card-foreground: 210 40% 96%;
  --popover: 228 12% 8%;
  --popover-foreground: 210 40% 96%;
  --primary: 217 91% 60%;
  --primary-foreground: 0 0% 100%;
  --secondary: 217 33% 17%;
  --secondary-foreground: 210 40% 96%;
  --muted: 228 10% 14%;
  --muted-foreground: 215 20% 65%;
  --accent: 24 95% 53%;
  --accent-foreground: 0 0% 100%;
  --destructive: 0 84% 60%;
  --destructive-foreground: 0 0% 100%;
  --border: 228 10% 16%;
  --input: 228 10% 16%;
  --ring: 217 91% 60%;
  --radius: 0.75rem;
  --success: 142 71% 45%;
  --warning: 38 92% 50%;
}

.dark {
  --background: 228 15% 4%;
  --foreground: 210 40% 96%;
  --card: 228 12% 8%;
  --card-foreground: 210 40% 96%;
  --popover: 228 12% 8%;
  --popover-foreground: 210 40% 96%;
  --primary: 217 91% 60%;
  --primary-foreground: 0 0% 100%;
  --secondary: 217 33% 17%;
  --secondary-foreground: 210 40% 96%;
  --muted: 228 10% 14%;
  --muted-foreground: 215 20% 65%;
  --accent: 24 95% 53%;
  --accent-foreground: 0 0% 100%;
  --destructive: 0 84% 60%;
  --destructive-foreground: 0 0% 100%;
  --border: 228 10% 16%;
  --input: 228 10% 16%;
  --ring: 217 91% 60%;
}

@theme inline {
  --color-background: hsl(var(--background));
  --color-foreground: hsl(var(--foreground));
  --color-card: hsl(var(--card));
  --color-card-foreground: hsl(var(--card-foreground));
  --color-popover: hsl(var(--popover));
  --color-popover-foreground: hsl(var(--popover-foreground));
  --color-primary: hsl(var(--primary));
  --color-primary-foreground: hsl(var(--primary-foreground));
  --color-secondary: hsl(var(--secondary));
  --color-secondary-foreground: hsl(var(--secondary-foreground));
  --color-muted: hsl(var(--muted));
  --color-muted-foreground: hsl(var(--muted-foreground));
  --color-accent: hsl(var(--accent));
  --color-accent-foreground: hsl(var(--accent-foreground));
  --color-destructive: hsl(var(--destructive));
  --color-destructive-foreground: hsl(var(--destructive-foreground));
  --color-border: hsl(var(--border));
  --color-input: hsl(var(--input));
  --color-ring: hsl(var(--ring));
  --color-success: hsl(var(--success));
  --color-warning: hsl(var(--warning));
  --radius-sm: calc(var(--radius) - 4px);
  --radius-md: calc(var(--radius) - 2px);
  --radius-lg: var(--radius);
  --radius-xl: calc(var(--radius) + 4px);
}

@layer base {
  * {
    @apply border-border;
  }
  body {
    @apply bg-background text-foreground;
    font-family: 'Inter', sans-serif;
  }
}

/* Custom scrollbar for dark theme */
::-webkit-scrollbar {
  width: 6px;
}
::-webkit-scrollbar-track {
  background: hsl(228 15% 4%);
}
::-webkit-scrollbar-thumb {
  background: hsl(228 10% 20%);
  border-radius: 3px;
}
::-webkit-scrollbar-thumb:hover {
  background: hsl(228 10% 28%);
}

ENDOFFILE

mkdir -p app
cat > 'app/layout.tsx' << 'ENDOFFILE'
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
// DO NOT remove this @/components/made-with-badge/made-with-badge file
import { MadeWithBadge } from "@/components/made-with-badge/made-with-badge";
/**
 * For the root page layout you can edit metadata in this file
 * @/components/root-metadata
 * Do not add a const metadata export here directly
 * 
 * and DO NOT remove this @/components/root-metadata file
 * only edit it
 */
import { metadata } from "@/components/root-metadata";
export { metadata }

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="dark">
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        {children}
        {/* DO NOT UNDER ANY CIRCUMSTANCES REMOVE THIS & DO NOT CHANGE made-with-badge contents */}
        <MadeWithBadge />
      </body>
    </html>
  );
}


ENDOFFILE

mkdir -p app/management
cat > 'app/management/page.tsx' << 'ENDOFFILE'
"use client";
import { useEffect, useState, useCallback } from "react";
import { useRouter } from "next/navigation";
import { getCurrentUser, logout, getTasks, createTask, getCandidateNames, refreshSlotStates, getFilteredTasks, formatDT, formatTime, Task, User, FilterState } from "@/lib/store";
import { motion, AnimatePresence } from "framer-motion";
import { Shield, LogOut, Plus, X, ClipboardList, Clock, AlertTriangle, CheckCircle2, Timer, ChevronDown, LayoutDashboard, ListChecks, ChevronRight, Image as ImageIcon, ExternalLink, Gauge, Search, Filter, RotateCcw } from "lucide-react";

const PLATFORMS = ["LinkedIn", "Twitter", "Instagram", "YouTube", "Other"];
const STATUSES = ["Pending", "In Progress", "Completed", "Issues", "Expired"];
const SORTS: { v: string; l: string }[] = [{v:"newest",l:"Newest First"},{v:"oldest",l:"Oldest First"},{v:"deadline-asc",l:"Deadline: Soonest"},{v:"deadline-desc",l:"Deadline: Latest"},{v:"score-high",l:"Score: High\u2192Low"},{v:"score-low",l:"Score: Low\u2192High"},{v:"candidate-az",l:"Candidate: A\u2192Z"},{v:"candidate-za",l:"Candidate: Z\u2192A"}];

export default function ManagementDashboard() {
  const router = useRouter();
  const [user, setUser] = useState<User | null>(null);
  const [allTasks, setAllTasks] = useState<Task[]>([]);
  const [showForm, setShowForm] = useState(false);
  const [expanded, setExpanded] = useState<string | null>(null);
  const [candidates, setCandidates] = useState<string[]>([]);
  const [filters, setFilters] = useState<FilterState>({ candidate: "", platform: "all", status: "all", sort: "newest" });
  const [taskName, setTaskName] = useState(""); const [checklist, setChecklist] = useState("");
  const [platform, setPlatform] = useState(PLATFORMS[0]); const [startDT, setStartDT] = useState(""); const [endDT, setEndDT] = useState("");
  const [candidateName, setCandidateName] = useState(""); const [formError, setFormError] = useState("");

  const refresh = useCallback(() => { refreshSlotStates(); setAllTasks(getTasks()); setCandidates(getCandidateNames()); }, []);
  useEffect(() => { const u = getCurrentUser(); if (!u || u.role !== "management") { router.push("/"); return; } setUser(u); refresh(); }, [router, refresh]);
  useEffect(() => { const iv = setInterval(() => { refreshSlotStates(); setAllTasks(getTasks()); }, 5000); return () => clearInterval(iv); }, []);

  const filtered = getFilteredTasks(allTasks, filters);
  const clearFilters = () => setFilters({ candidate: "", platform: "all", status: "all", sort: "newest" });
  const hasFilters = filters.candidate || filters.platform !== "all" || filters.status !== "all" || filters.sort !== "newest";

  const handleCreate = (e: React.FormEvent) => {
    e.preventDefault(); setFormError("");
    if (!taskName.trim() || !checklist.trim() || !startDT || !endDT || !candidateName.trim()) { setFormError("All fields required."); return; }
    if (new Date(endDT) <= new Date(startDT)) { setFormError("End must be after start."); return; }
    createTask({ name: taskName.trim(), checklist: checklist.trim(), platform, startTime: new Date(startDT).toISOString(), endTime: new Date(endDT).toISOString(), candidate: candidateName.trim(), createdBy: user?.id || "" });
    setTaskName(""); setChecklist(""); setPlatform(PLATFORMS[0]); setStartDT(""); setEndDT(""); setCandidateName(""); setShowForm(false); refresh();
  };

  const sBadge = (s: string) => ({ Completed: "bg-emerald-500/15 text-emerald-400 border-emerald-500/25", Issues: "bg-amber-500/15 text-amber-400 border-amber-500/25", Expired: "bg-red-500/15 text-red-400 border-red-500/25", "In Progress": "bg-blue-500/15 text-blue-400 border-blue-500/25", Pending: "bg-slate-500/15 text-slate-400 border-slate-500/25" }[s] || "bg-slate-500/15 text-slate-400 border-slate-500/25");
  const slotBadge = (s: string) => ({ submitted: "bg-emerald-500/15 text-emerald-400", upload_open: "bg-green-500/15 text-green-400", working: "bg-blue-500/15 text-blue-400", locked: "bg-slate-500/10 text-slate-500", missed: "bg-red-500/15 text-red-400" }[s] || "bg-slate-500/10 text-slate-500");
  const total = allTasks.length; const completed = allTasks.filter(t => t.status === "Completed").length;
  const inProg = allTasks.filter(t => t.status === "In Progress").length; const issues = allTasks.filter(t => ["Issues", "Expired"].includes(t.status)).length;
  const selCls = "w-full px-3 py-2 rounded-lg bg-muted/50 border border-border/60 text-foreground focus:outline-none focus:ring-2 focus:ring-primary/40 text-sm appearance-none pr-8";

  if (!user) return null;
  return (
    <div className="min-h-screen" style={{ background: "linear-gradient(180deg, #06060a 0%, #0a0a12 100%)" }}>
      <header className="sticky top-0 z-40 border-b border-border/40 bg-background/80 backdrop-blur-xl">
        <div className="max-w-[1400px] mx-auto px-4 sm:px-6 h-14 flex items-center justify-between">
          <div className="flex items-center gap-3"><div className="w-8 h-8 rounded-lg bg-primary/10 border border-primary/20 flex items-center justify-center"><Shield className="w-4 h-4 text-primary" /></div><div><h1 className="text-sm font-semibold text-foreground leading-none">TaskEval</h1><p className="text-[11px] text-muted-foreground">Management</p></div></div>
          <div className="flex items-center gap-3"><span className="text-xs text-muted-foreground hidden sm:inline">{user.name}</span><button onClick={() => { logout(); router.push("/"); }} className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground px-2.5 py-1.5 rounded-lg hover:bg-muted/50"><LogOut className="w-3.5 h-3.5" /> Logout</button></div>
        </div>
      </header>
      <main className="max-w-[1400px] mx-auto px-4 sm:px-6 py-6">
        {/* Stats */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6">
          {[{ l:"Total",v:total,icon:LayoutDashboard,c:"text-primary",bg:"bg-primary/10" },{ l:"Completed",v:completed,icon:CheckCircle2,c:"text-emerald-400",bg:"bg-emerald-500/10" },{ l:"In Progress",v:inProg,icon:Timer,c:"text-blue-400",bg:"bg-blue-500/10" },{ l:"Issues",v:issues,icon:AlertTriangle,c:"text-red-400",bg:"bg-red-500/10" }].map(s=>(<div key={s.l} className="rounded-xl border border-border/40 bg-card/50 p-4"><div className="flex items-center gap-2 mb-2"><div className={`w-7 h-7 rounded-lg ${s.bg} flex items-center justify-center`}><s.icon className={`w-3.5 h-3.5 ${s.c}`}/></div><span className="text-xs text-muted-foreground">{s.l}</span></div><p className="text-2xl font-bold text-foreground">{s.v}</p></div>))}
        </div>

        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-foreground flex items-center gap-2"><ListChecks className="w-5 h-5 text-primary" /> All Tasks</h2>
          <button onClick={() => setShowForm(!showForm)} className="flex items-center gap-2 px-4 py-2 rounded-lg bg-primary text-primary-foreground text-sm font-medium hover:bg-primary/90 shadow-lg shadow-primary/20">{showForm ? <X className="w-4 h-4" /> : <Plus className="w-4 h-4" />} {showForm ? "Cancel" : "New Task"}</button>
        </div>

        {/* Create Form */}
        <AnimatePresence>{showForm && (
          <motion.div initial={{ opacity:0,height:0 }} animate={{ opacity:1,height:"auto" }} exit={{ opacity:0,height:0 }} className="overflow-hidden">
            <div className="rounded-xl border border-primary/20 bg-card/80 p-5 mb-6">
              <h3 className="text-sm font-semibold text-foreground mb-4 flex items-center gap-2"><ClipboardList className="w-4 h-4 text-primary" /> Create New Task</h3>
              {formError && <div className="text-destructive text-xs bg-destructive/10 border border-destructive/20 rounded-lg px-3 py-2 mb-3 flex items-center gap-2"><AlertTriangle className="w-3.5 h-3.5" />{formError}</div>}
              <form onSubmit={handleCreate} className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div><label className="block text-xs font-medium text-muted-foreground uppercase tracking-wider mb-1">Task Name</label><input type="text" value={taskName} onChange={e=>setTaskName(e.target.value)} placeholder="e.g., Publish LinkedIn Post" className="w-full px-3 py-2 rounded-lg bg-muted/50 border border-border/60 text-foreground placeholder-muted-foreground/50 focus:outline-none focus:ring-2 focus:ring-primary/40 text-sm" /></div>
                <div><label className="block text-xs font-medium text-muted-foreground uppercase tracking-wider mb-1">Checklist (comma sep)</label><input type="text" value={checklist} onChange={e=>setChecklist(e.target.value)} placeholder="Include 3 hashtags, Tag connection" className="w-full px-3 py-2 rounded-lg bg-muted/50 border border-border/60 text-foreground placeholder-muted-foreground/50 focus:outline-none focus:ring-2 focus:ring-primary/40 text-sm" /></div>
                <div><label className="block text-xs font-medium text-muted-foreground uppercase tracking-wider mb-1">Platform</label><div className="relative"><select value={platform} onChange={e=>setPlatform(e.target.value)} className={selCls}>{PLATFORMS.map(p=><option key={p} value={p} className="bg-card">{p}</option>)}</select><ChevronDown className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground pointer-events-none" /></div></div>
                <div><label className="block text-xs font-medium text-muted-foreground uppercase tracking-wider mb-1">Candidate</label><input type="text" value={candidateName} onChange={e=>setCandidateName(e.target.value)} placeholder="Candidate name" className="w-full px-3 py-2 rounded-lg bg-muted/50 border border-border/60 text-foreground placeholder-muted-foreground/50 focus:outline-none focus:ring-2 focus:ring-primary/40 text-sm" list="cs" /><datalist id="cs">{candidates.map(c=><option key={c} value={c} />)}</datalist></div>
                <div><label className="block text-xs font-medium text-muted-foreground uppercase tracking-wider mb-1">Start Date & Time</label><input type="datetime-local" value={startDT} onChange={e=>setStartDT(e.target.value)} className="w-full px-3 py-2 rounded-lg bg-muted/50 border border-border/60 text-foreground focus:outline-none focus:ring-2 focus:ring-primary/40 text-sm [color-scheme:dark]" /></div>
                <div><label className="block text-xs font-medium text-muted-foreground uppercase tracking-wider mb-1">End Date & Time</label><input type="datetime-local" value={endDT} onChange={e=>setEndDT(e.target.value)} className="w-full px-3 py-2 rounded-lg bg-muted/50 border border-border/60 text-foreground focus:outline-none focus:ring-2 focus:ring-primary/40 text-sm [color-scheme:dark]" /></div>
                <div className="sm:col-span-2 flex justify-end"><button type="submit" className="px-6 py-2 rounded-lg bg-primary text-primary-foreground text-sm font-medium hover:bg-primary/90 shadow-lg shadow-primary/20 flex items-center gap-2"><Plus className="w-4 h-4" /> Create Task</button></div>
              </form>
            </div>
          </motion.div>
        )}</AnimatePresence>

        {/* Filter Bar */}
        <div className="rounded-xl border border-border/40 bg-card/30 p-3 mb-3 flex flex-wrap items-center gap-3">
          <div className="relative flex-1 min-w-[180px]"><Search className="absolute left-3 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-muted-foreground" /><input type="text" value={filters.candidate} onChange={e=>setFilters({...filters, candidate: e.target.value})} placeholder="Search by candidate..." className="w-full pl-9 pr-3 py-1.5 rounded-lg bg-muted/50 border border-border/60 text-foreground placeholder-muted-foreground/50 focus:outline-none focus:ring-2 focus:ring-primary/40 text-xs" /></div>
          <div className="relative"><select value={filters.platform} onChange={e=>setFilters({...filters, platform: e.target.value})} className="pl-3 pr-7 py-1.5 rounded-lg bg-muted/50 border border-border/60 text-foreground text-xs focus:outline-none focus:ring-2 focus:ring-primary/40 appearance-none"><option value="all">All Platforms</option>{PLATFORMS.map(p=><option key={p} value={p}>{p}</option>)}</select><ChevronDown className="absolute right-2 top-1/2 -translate-y-1/2 w-3 h-3 text-muted-foreground pointer-events-none" /></div>
          <div className="relative"><select value={filters.status} onChange={e=>setFilters({...filters, status: e.target.value})} className="pl-3 pr-7 py-1.5 rounded-lg bg-muted/50 border border-border/60 text-foreground text-xs focus:outline-none focus:ring-2 focus:ring-primary/40 appearance-none"><option value="all">All Statuses</option>{STATUSES.map(s=><option key={s} value={s}>{s}</option>)}</select><ChevronDown className="absolute right-2 top-1/2 -translate-y-1/2 w-3 h-3 text-muted-foreground pointer-events-none" /></div>
          <div className="relative"><select value={filters.sort} onChange={e=>setFilters({...filters, sort: e.target.value})} className="pl-3 pr-7 py-1.5 rounded-lg bg-muted/50 border border-border/60 text-foreground text-xs focus:outline-none focus:ring-2 focus:ring-primary/40 appearance-none">{SORTS.map(s=><option key={s.v} value={s.v}>{s.l}</option>)}</select><ChevronDown className="absolute right-2 top-1/2 -translate-y-1/2 w-3 h-3 text-muted-foreground pointer-events-none" /></div>
          {hasFilters && <button onClick={clearFilters} className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"><RotateCcw className="w-3 h-3" /> Clear</button>}
        </div>

        {/* Result count */}
        <div className="text-xs text-muted-foreground mb-2">Showing {filtered.length} of {allTasks.length} tasks</div>

        {/* Task List */}
        {filtered.length === 0 ? (
          <div className="rounded-xl border border-border/40 bg-card/30 p-12 text-center"><Filter className="w-10 h-10 text-muted-foreground/30 mx-auto mb-3" /><p className="text-muted-foreground text-sm">{allTasks.length === 0 ? "No tasks yet." : "No tasks match your current filters."}</p>{hasFilters && <button onClick={clearFilters} className="mt-2 text-xs text-primary hover:underline">Clear Filters</button>}</div>
        ) : (
          <div className="space-y-3">
            {filtered.map(task => (
              <div key={task.id} className="rounded-xl border border-border/40 bg-card/50 overflow-hidden">
                <button onClick={() => setExpanded(expanded === task.id ? null : task.id)} className="w-full p-4 flex items-center gap-4 text-left hover:bg-card/70 transition-colors">
                  <ChevronRight className={`w-4 h-4 text-muted-foreground shrink-0 transition-transform ${expanded === task.id ? "rotate-90" : ""}`} />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap mb-1">
                      <span className="text-[11px] font-mono text-muted-foreground bg-muted/50 px-1.5 py-0.5 rounded">{task.id}</span>
                      <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-medium border ${sBadge(task.status)}`}>{task.status}</span>
                      <span className="text-[11px] text-muted-foreground bg-muted/30 px-1.5 py-0.5 rounded">{task.platform}</span>
                      <span className="text-[11px] font-medium bg-amber-500/15 text-amber-400 border border-amber-500/25 px-2 py-0.5 rounded-full flex items-center gap-1"><Gauge className="w-3 h-3" />{task.durationMultiplier}\u00d7</span>
                    </div>
                    <h3 className="text-sm font-semibold text-foreground truncate">{task.name}</h3>
                    <div className="flex flex-wrap gap-x-4 gap-y-1 mt-1 text-xs text-muted-foreground">
                      <span>Candidate: <span className="text-foreground">{task.candidate}</span></span>
                      <span>{task.slots.length} slots \u00b7 {task.pointsPerSlot} pts/slot</span>
                      <span>{formatDT(task.startTime)} \u2192 {formatDT(task.endTime)}</span>
                    </div>
                  </div>
                  <div className="text-right shrink-0"><div className="text-2xl font-bold text-foreground">{task.score}<span className="text-xs text-muted-foreground font-normal">/100</span></div>{task.totalDeductions > 0 && <div className="text-xs text-red-400 font-mono">-{task.totalDeductions}</div>}</div>
                </button>
                <AnimatePresence>{expanded === task.id && (
                  <motion.div initial={{height:0}} animate={{height:"auto"}} exit={{height:0}} className="overflow-hidden">
                    <div className="border-t border-border/20 bg-muted/10">
                      <div className="p-3 text-xs text-muted-foreground flex flex-wrap gap-x-4"><span>Checklist: <span className="text-foreground">{task.checklist.join(", ")}</span></span><span>Multiplier: <span className="text-amber-400 font-semibold">{task.durationMultiplier}\u00d7</span></span></div>
                      <div className="overflow-x-auto"><table className="w-full text-xs"><thead><tr className="border-y border-border/20 bg-muted/20">
                        <th className="px-3 py-2 text-left text-muted-foreground font-medium">Slot</th>
                        <th className="px-3 py-2 text-left text-muted-foreground font-medium">Work</th>
                        <th className="px-3 py-2 text-left text-muted-foreground font-medium">Upload</th>
                        <th className="px-3 py-2 text-left text-muted-foreground font-medium">Worth</th>
                        <th className="px-3 py-2 text-left text-muted-foreground font-medium">Screenshot</th>
                        <th className="px-3 py-2 text-left text-muted-foreground font-medium">Summary</th>
                        <th className="px-3 py-2 text-left text-muted-foreground font-medium">Output</th>
                        <th className="px-3 py-2 text-left text-muted-foreground font-medium">Completion</th>
                        <th className="px-3 py-2 text-left text-muted-foreground font-medium">Errors</th>
                        <th className="px-3 py-2 text-left text-muted-foreground font-medium">Ded.</th>
                        <th className="px-3 py-2 text-left text-muted-foreground font-medium">Status</th>
                      </tr></thead><tbody className="divide-y divide-border/10">
                        {task.slots.map(slot=>(<tr key={slot.slotIndex} className="hover:bg-card/30">
                          <td className="px-3 py-2 font-mono text-muted-foreground">#{slot.slotIndex+1}{slot.isLast?" (last)":""}</td>
                          <td className="px-3 py-2 text-muted-foreground whitespace-nowrap">{formatTime(slot.startTime)}\u2013{formatTime(slot.workEndTime)}</td>
                          <td className="px-3 py-2 text-muted-foreground whitespace-nowrap">{formatTime(slot.workEndTime)}\u2013{formatTime(slot.uploadEndTime)}</td>
                          <td className="px-3 py-2 font-mono text-primary/70">{task.pointsPerSlot}</td>
                          <td className="px-3 py-2">{slot.uploads.screenshot ? <span className="text-emerald-400 flex items-center gap-1"><ImageIcon className="w-3 h-3" />Yes</span> : <span className="text-muted-foreground/40">\u2014</span>}</td>
                          <td className="px-3 py-2 max-w-[150px] truncate">{slot.uploads.summary || <span className="text-muted-foreground/40">\u2014</span>}</td>
                          <td className="px-3 py-2">{slot.uploads.outputLink ? <a href={slot.uploads.outputLink} target="_blank" rel="noopener noreferrer" className="text-primary hover:underline flex items-center gap-1"><ExternalLink className="w-3 h-3" />Link</a> : <span className="text-muted-foreground/40">{slot.isLast?"Req":"\u2014"}</span>}</td>
                          <td className="px-3 py-2">{slot.isLast ? (slot.uploads.completionStatus === 'completed' ? <span className="text-emerald-400">\u2705 Completed</span> : slot.uploads.completionStatus === 'pending' ? <span className="text-amber-400">\u23f3 Pending</span> : <span className="text-muted-foreground/40">\u2014</span>) : <span className="text-muted-foreground/40">\u2014</span>}</td>
                          <td className="px-3 py-2">{slot.errors.length>0?<div className="space-y-0.5">{slot.errors.map((e,i)=><div key={i} className="text-red-400/80 leading-tight">{e}</div>)}</div>:<span className="text-muted-foreground/40">\u2014</span>}</td>
                          <td className="px-3 py-2 font-mono">{slot.deductions>0?<span className="text-red-400">-{slot.deductions}</span>:<span className="text-muted-foreground/40">0</span>}</td>
                          <td className="px-3 py-2"><span className={`px-2 py-0.5 rounded-full text-[10px] font-medium ${slotBadge(slot.status)}`}>{slot.status}</span></td>
                        </tr>))}
                      </tbody></table></div>
                    </div>
                  </motion.div>
                )}</AnimatePresence>
              </div>
            ))}
          </div>
        )}
      </main>
    </div>
  );
}

ENDOFFILE

mkdir -p app/candidate
cat > 'app/candidate/page.tsx' << 'ENDOFFILE'
"use client";
import { useEffect, useState, useRef } from "react";
import { useRouter } from "next/navigation";
import { getCurrentUser, logout, getTasksForCandidate, refreshSlotStates, submitSlot, getSlotLiveState, formatDT, formatTime, formatCountdown, Task, User } from "@/lib/store";
import { motion, AnimatePresence } from "framer-motion";
import { UserCheck, LogOut, Clock, AlertTriangle, CheckCircle2, Upload, Lock, Ban, ExternalLink, ClipboardList, Zap, Eye, X, FileText, Link as LinkIcon, Gauge, Hammer } from "lucide-react";

export default function CandidateDashboard() {
  const router = useRouter();
  const [user, setUser] = useState<User | null>(null);
  const [tasks, setTasks] = useState<Task[]>([]);
  const [tick, setTick] = useState(0);
  const [previewImg, setPreviewImg] = useState<string | null>(null);
  const [activeSlot, setActiveSlot] = useState<{ taskId: string; slotIndex: number } | null>(null);
  const [slotScreenshot, setSlotScreenshot] = useState<{ data: string; name: string } | null>(null);
  const [slotSummary, setSlotSummary] = useState("");
  const [slotLink, setSlotLink] = useState("");
  const [slotCompletion, setSlotCompletion] = useState<'completed' | 'pending' | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const fileRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => { const u = getCurrentUser(); if (!u || u.role !== "candidate") { router.push("/"); return; } setUser(u); }, [router]);
  useEffect(() => { if (!user) return; refreshSlotStates(); setTasks(getTasksForCandidate(user.name)); const iv = setInterval(() => { setTick(t => t + 1); refreshSlotStates(); setTasks(getTasksForCandidate(user!.name)); }, 1000); return () => clearInterval(iv); }, [user]);

  const resetModal = () => { setActiveSlot(null); setSlotScreenshot(null); setSlotSummary(""); setSlotLink(""); setSlotCompletion(null); };
  const handleFile = (f: File) => { if (!f.type.startsWith("image/")) { alert("Image only."); return; } const r = new FileReader(); r.onload = () => setSlotScreenshot({ data: r.result as string, name: f.name }); r.readAsDataURL(f); };

  const handleSubmit = () => {
    if (!activeSlot || !slotScreenshot) return;
    const t = tasks.find(t => t.id === activeSlot.taskId);
    const s = t?.slots[activeSlot.slotIndex];
    if (s?.isLast && !slotCompletion) return; // Final slot needs completion status
    setSubmitting(true);
    submitSlot(activeSlot.taskId, activeSlot.slotIndex, slotScreenshot.data, slotScreenshot.name, slotSummary.trim(), slotLink.trim() || undefined, s?.isLast ? (slotCompletion || undefined) : undefined);
    resetModal(); setSubmitting(false);
    if (user) { refreshSlotStates(); setTasks(getTasksForCandidate(user.name)); }
  };

  const slotColor = (s: string) => ({ submitted: "border-emerald-500/40 bg-emerald-500/5", upload_open: "border-green-500/60 bg-green-500/5 shadow-green-500/10 shadow-lg", working: "border-blue-500/40 bg-blue-500/5", locked: "border-border/30 bg-card/30", missed: "border-red-500/40 bg-red-500/5" }[s] || "border-border/30 bg-card/30");
  const slotIcon = (s: string) => ({ submitted: <CheckCircle2 className="w-4 h-4 text-emerald-400" />, upload_open: <Upload className="w-4 h-4 text-green-400" />, working: <Hammer className="w-4 h-4 text-blue-400" />, locked: <Lock className="w-4 h-4 text-slate-500" />, missed: <Ban className="w-4 h-4 text-red-400" /> }[s] || <Lock className="w-4 h-4 text-slate-500" />);
  const statusBadge = (s: string) => ({ Completed: "bg-emerald-500/15 text-emerald-400 border-emerald-500/25", Issues: "bg-amber-500/15 text-amber-400 border-amber-500/25", Expired: "bg-red-500/15 text-red-400 border-red-500/25", "In Progress": "bg-blue-500/15 text-blue-400 border-blue-500/25", Pending: "bg-slate-500/15 text-slate-400 border-slate-500/25" }[s] || "bg-slate-500/15 text-slate-400 border-slate-500/25");

  if (!user) return null;

  // Get active slot info for modal
  const activeTask = activeSlot ? tasks.find(t => t.id === activeSlot.taskId) : null;
  const activeSlotObj = activeTask?.slots[activeSlot?.slotIndex ?? -1];
  const isFinalSlot = activeSlotObj?.isLast ?? false;
  const canSubmit = slotScreenshot && slotSummary.trim() && (!isFinalSlot || (slotLink.trim() && slotCompletion));

  return (
    <div className="min-h-screen" style={{ background: "linear-gradient(180deg, #06060a 0%, #0a0a12 100%)" }}>
      {/* Image Preview */}
      <AnimatePresence>{previewImg && (
        <motion.div initial={{ opacity:0 }} animate={{ opacity:1 }} exit={{ opacity:0 }} className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-sm p-4" onClick={() => setPreviewImg(null)}>
          <motion.div initial={{ scale:0.9 }} animate={{ scale:1 }} exit={{ scale:0.9 }} className="relative max-w-3xl max-h-[85vh] rounded-xl overflow-hidden border border-border/40" onClick={e => e.stopPropagation()}>
            <button onClick={() => setPreviewImg(null)} className="absolute top-3 right-3 z-10 w-8 h-8 rounded-full bg-black/60 flex items-center justify-center text-white"><X className="w-4 h-4" /></button>
            <img src={previewImg} alt="Screenshot" className="max-w-full max-h-[85vh] object-contain" />
          </motion.div>
        </motion.div>
      )}</AnimatePresence>

      {/* Submit Modal */}
      <AnimatePresence>{activeSlot && (
        <motion.div initial={{ opacity:0 }} animate={{ opacity:1 }} exit={{ opacity:0 }} className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-sm p-4" onClick={resetModal}>
          <motion.div initial={{ scale:0.95,y:10 }} animate={{ scale:1,y:0 }} exit={{ scale:0.95,y:10 }} className="w-full max-w-lg rounded-2xl border border-primary/20 bg-card p-6 shadow-2xl max-h-[90vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
            <h3 className="text-base font-semibold text-foreground mb-1 flex items-center gap-2"><Upload className="w-5 h-5 text-green-400" /> Submit Slot #{(activeSlot.slotIndex) + 1}{isFinalSlot ? " (Final)" : ""}</h3>
            <p className="text-xs text-muted-foreground mb-5">{activeTask?.name} — Upload: {activeSlotObj ? `${formatTime(activeSlotObj.workEndTime)}–${formatTime(activeSlotObj.uploadEndTime)}` : ""}</p>
            <div className="space-y-4">
              {/* Screenshot */}
              <div><label className="block text-xs font-medium text-muted-foreground uppercase tracking-wider mb-1.5">Screenshot *</label>
                <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={e => { const f = e.target.files?.[0]; if (f) handleFile(f); }} />
                {slotScreenshot ? (<div className="flex items-center gap-3 p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/20"><CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0" /><span className="text-sm text-emerald-300 truncate flex-1">{slotScreenshot.name}</span><button onClick={() => setSlotScreenshot(null)} className="text-xs text-muted-foreground hover:text-foreground">Change</button></div>
                ) : (<button onClick={() => fileRef.current?.click()} className="w-full flex items-center justify-center gap-2 p-4 rounded-lg border-2 border-dashed border-border/60 text-muted-foreground hover:border-green-500/40 hover:text-green-400 transition-colors text-sm"><Upload className="w-4 h-4" /> Upload screenshot</button>)}
              </div>
              {/* Summary */}
              <div><label className="block text-xs font-medium text-muted-foreground uppercase tracking-wider mb-1.5">Summary *</label>
                <textarea value={slotSummary} onChange={e => setSlotSummary(e.target.value)} rows={3} placeholder="Describe what you completed..." className="w-full px-3 py-2 rounded-lg bg-muted/50 border border-border/60 text-foreground placeholder-muted-foreground/50 focus:outline-none focus:ring-2 focus:ring-primary/40 text-sm resize-none" />
              </div>
              {/* Output Link (final only) */}
              {isFinalSlot && (<div><label className="block text-xs font-medium text-muted-foreground uppercase tracking-wider mb-1.5">Output Link *</label>
                <div className="relative"><LinkIcon className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" /><input type="url" value={slotLink} onChange={e => setSlotLink(e.target.value)} placeholder="https://..." className="w-full pl-10 pr-4 py-2.5 rounded-lg bg-muted/50 border border-border/60 text-foreground placeholder-muted-foreground/50 focus:outline-none focus:ring-2 focus:ring-primary/40 text-sm" /></div>
              </div>)}
              {/* Completion Status Toggle (final only) */}
              {isFinalSlot && (
                <div>
                  <label className="block text-xs font-medium text-muted-foreground uppercase tracking-wider mb-2">Task Completion Status *</label>
                  <div className="grid grid-cols-2 gap-3">
                    <button type="button" onClick={() => setSlotCompletion('completed')}
                      className={`p-3 rounded-lg border text-left transition-all ${slotCompletion === 'completed' ? 'border-emerald-500/60 bg-emerald-500/10' : 'border-border/60 bg-muted/30 hover:border-border'}`}>
                      <div className="flex items-center gap-2 mb-1"><CheckCircle2 className={`w-4 h-4 ${slotCompletion === 'completed' ? 'text-emerald-400' : 'text-muted-foreground/50'}`} /><span className={`text-sm font-medium ${slotCompletion === 'completed' ? 'text-emerald-400' : 'text-muted-foreground'}`}>Completed</span></div>
                      <p className="text-[11px] text-muted-foreground">All deliverables done</p>
                    </button>
                    <button type="button" onClick={() => setSlotCompletion('pending')}
                      className={`p-3 rounded-lg border text-left transition-all ${slotCompletion === 'pending' ? 'border-amber-500/60 bg-amber-500/10' : 'border-border/60 bg-muted/30 hover:border-border'}`}>
                      <div className="flex items-center gap-2 mb-1"><Clock className={`w-4 h-4 ${slotCompletion === 'pending' ? 'text-amber-400' : 'text-muted-foreground/50'}`} /><span className={`text-sm font-medium ${slotCompletion === 'pending' ? 'text-amber-400' : 'text-muted-foreground'}`}>Pending</span></div>
                      <p className="text-[11px] text-muted-foreground">Some items still in progress</p>
                    </button>
                  </div>
                </div>
              )}
            </div>
            <div className="flex gap-3 mt-6">
              <button onClick={resetModal} className="flex-1 py-2.5 rounded-lg border border-border/60 text-muted-foreground text-sm font-medium hover:bg-muted/30">Cancel</button>
              <button onClick={handleSubmit} disabled={!canSubmit || submitting} className="flex-1 py-2.5 rounded-lg bg-green-600 text-white text-sm font-semibold hover:bg-green-500 shadow-lg shadow-green-600/20 disabled:opacity-40 disabled:cursor-not-allowed flex items-center justify-center gap-2"><CheckCircle2 className="w-4 h-4" /> Submit</button>
            </div>
          </motion.div>
        </motion.div>
      )}</AnimatePresence>

      <header className="sticky top-0 z-40 border-b border-border/40 bg-background/80 backdrop-blur-xl">
        <div className="max-w-[1200px] mx-auto px-4 sm:px-6 h-14 flex items-center justify-between">
          <div className="flex items-center gap-3"><div className="w-8 h-8 rounded-lg bg-primary/10 border border-primary/20 flex items-center justify-center"><UserCheck className="w-4 h-4 text-primary" /></div><div><h1 className="text-sm font-semibold text-foreground leading-none">TaskEval</h1><p className="text-[11px] text-muted-foreground">Candidate</p></div></div>
          <div className="flex items-center gap-3"><span className="text-xs text-muted-foreground hidden sm:inline">Welcome, {user.name}</span><button onClick={() => { logout(); router.push("/"); }} className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground px-2.5 py-1.5 rounded-lg hover:bg-muted/50"><LogOut className="w-3.5 h-3.5" /> Logout</button></div>
        </div>
      </header>

      <main className="max-w-[1200px] mx-auto px-4 sm:px-6 py-6">
        <h2 className="text-lg font-semibold text-foreground flex items-center gap-2 mb-4"><Zap className="w-5 h-5 text-primary" /> My Tasks</h2>
        {tasks.length === 0 ? (
          <div className="rounded-xl border border-border/40 bg-card/30 p-12 text-center"><ClipboardList className="w-10 h-10 text-muted-foreground/30 mx-auto mb-3" /><p className="text-muted-foreground text-sm">No tasks assigned.</p></div>
        ) : (
          <div className="space-y-6">
            {tasks.map(task => {
              const shiftH = ((new Date(task.endTime).getTime() - new Date(task.startTime).getTime()) / 3600000).toFixed(1);
              return (
              <div key={task.id} className="rounded-xl border border-border/40 bg-card/50 overflow-hidden">
                <div className="p-4">
                  <div className="flex items-start justify-between gap-3 mb-2">
                    <div>
                      <div className="flex items-center gap-2 flex-wrap mb-1"><span className="text-[11px] font-mono text-muted-foreground bg-muted/50 px-1.5 py-0.5 rounded">{task.id}</span><span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-medium border ${statusBadge(task.status)}`}>{task.status}</span><span className="text-[11px] text-muted-foreground bg-muted/30 px-1.5 py-0.5 rounded">{task.platform}</span></div>
                      <h3 className="text-sm font-semibold text-foreground">{task.name}</h3>
                      <p className="text-xs text-muted-foreground mt-0.5">Checklist: {task.checklist.join(", ")}</p>
                      <p className="text-xs text-muted-foreground">{formatDT(task.startTime)} → {formatDT(task.endTime)} · {task.slots.length} slots · {task.pointsPerSlot} pts/slot</p>
                      <div className="mt-2 flex items-center gap-3 text-[11px] bg-amber-500/8 border border-amber-500/15 rounded-lg px-3 py-1.5">
                        <Gauge className="w-3.5 h-3.5 text-amber-400 shrink-0" />
                        <span className="text-amber-300">Shift: {shiftH}h · Rate: {task.durationMultiplier}× · Missed slot: -{task.pointsPerSlot} pts</span>
                      </div>
                    </div>
                    <div className="text-right shrink-0"><div className="text-2xl font-bold text-foreground">{task.score}<span className="text-xs text-muted-foreground font-normal">/100</span></div></div>
                  </div>
                </div>
                <div className="border-t border-border/20 bg-muted/5 p-4 space-y-2">
                  {task.slots.map(slot => {
                    const live = getSlotLiveState(slot);
                    return (
                      <div key={slot.slotIndex} className={`rounded-lg border p-3 transition-all ${slotColor(live.state)}`}>
                        <div className="flex items-center justify-between gap-3">
                          <div className="flex items-center gap-2 flex-wrap">
                            {slotIcon(live.state)}
                            <span className="text-xs font-mono text-muted-foreground">Slot #{slot.slotIndex + 1}{slot.isLast ? " (Final)" : ""}</span>
                            <span className="text-[10px] text-muted-foreground/60">Work: {formatTime(slot.startTime)}–{formatTime(slot.workEndTime)} · Upload: {formatTime(slot.workEndTime)}–{formatTime(slot.uploadEndTime)}</span>
                            <span className="text-[10px] text-primary/50">Worth: {task.pointsPerSlot} pts</span>
                          </div>
                          <div className="flex items-center gap-2 shrink-0">
                            {live.state === "locked" && <span className="text-xs text-slate-500">Opens in {formatCountdown(live.remainingMs)}</span>}
                            {live.state === "working" && <span className="text-xs text-blue-400 font-mono">Upload in {formatCountdown(live.remainingMs)}</span>}
                            {live.state === "upload_open" && (<>
                              <span className="text-xs text-green-400 font-mono font-semibold">{formatCountdown(live.remainingMs)} left</span>
                              <button onClick={() => { setActiveSlot({ taskId: task.id, slotIndex: slot.slotIndex }); setSlotCompletion(null); }} className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-green-600 text-white text-xs font-medium hover:bg-green-500 shadow-lg shadow-green-600/20 animate-pulse"><Upload className="w-3 h-3" /> Upload Now</button>
                            </>)}
                            {live.state === "submitted" && (<div className="flex items-center gap-2">
                              {slot.uploads.screenshot && <button onClick={() => setPreviewImg(slot.uploads.screenshot)} className="text-xs text-emerald-400 bg-emerald-500/10 px-2 py-1 rounded border border-emerald-500/20 flex items-center gap-1"><Eye className="w-3 h-3" /> Img</button>}
                              {slot.uploads.outputLink && <a href={slot.uploads.outputLink} target="_blank" rel="noopener noreferrer" className="text-xs text-primary bg-primary/10 px-2 py-1 rounded border border-primary/20 flex items-center gap-1"><ExternalLink className="w-3 h-3" /> Link</a>}
                              {slot.isLast && slot.uploads.completionStatus && (
                                <span className={`text-[10px] px-2 py-0.5 rounded-full border ${slot.uploads.completionStatus === 'completed' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20' : 'bg-amber-500/10 text-amber-400 border-amber-500/20'}`}>
                                  {slot.uploads.completionStatus === 'completed' ? '✅ Completed' : '⏳ Pending'}
                                </span>
                              )}
                              <span className="text-[10px] text-emerald-400">{formatTime(slot.submittedAt!)}</span>
                              {slot.deductions > 0 && <span className="text-xs text-red-400 font-mono">-{slot.deductions}</span>}
                            </div>)}
                            {live.state === "missed" && <span className="text-xs text-red-400 font-medium">Missed — -{slot.deductions} pts</span>}
                          </div>
                        </div>
                        {live.state === "submitted" && slot.uploads.summary && (
                          <div className="mt-2 text-xs text-muted-foreground bg-muted/30 rounded px-2 py-1.5 flex items-start gap-1.5"><FileText className="w-3 h-3 shrink-0 mt-0.5" /> <span className="line-clamp-2">{slot.uploads.summary}</span></div>
                        )}
                        {slot.errors.length > 0 && live.state === "submitted" && (
                          <div className="mt-1.5 flex flex-wrap gap-1">{slot.errors.map((e, i) => <span key={i} className="text-[10px] text-red-400/80 bg-red-500/10 px-2 py-0.5 rounded-full border border-red-500/15">{e}</span>)}</div>
                        )}
                      </div>
                    );
                  })}
                </div>
              </div>);})}
          </div>
        )}
      </main>
    </div>
  );
}

ENDOFFILE

cat > 'package.json' << 'ENDOFFILE'
{
  "name": "nextjs",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "eslint"
  },
  "dependencies": {
    "@hookform/resolvers": "^5.2.2",
    "@radix-ui/react-accordion": "^1.2.12",
    "@radix-ui/react-alert-dialog": "^1.1.15",
    "@radix-ui/react-aspect-ratio": "^1.1.8",
    "@radix-ui/react-avatar": "^1.1.11",
    "@radix-ui/react-checkbox": "^1.3.3",
    "@radix-ui/react-collapsible": "^1.1.12",
    "@radix-ui/react-context-menu": "^2.2.16",
    "@radix-ui/react-dialog": "^1.1.15",
    "@radix-ui/react-dropdown-menu": "^2.1.16",
    "@radix-ui/react-hover-card": "^1.1.15",
    "@radix-ui/react-label": "^2.1.8",
    "@radix-ui/react-menubar": "^1.1.16",
    "@radix-ui/react-navigation-menu": "^1.2.14",
    "@radix-ui/react-popover": "^1.1.15",
    "@radix-ui/react-progress": "^1.1.8",
    "@radix-ui/react-radio-group": "^1.3.8",
    "@radix-ui/react-scroll-area": "^1.2.10",
    "@radix-ui/react-select": "^2.2.6",
    "@radix-ui/react-separator": "^1.1.8",
    "@radix-ui/react-slider": "^1.3.6",
    "@radix-ui/react-slot": "^1.2.4",
    "@radix-ui/react-switch": "^1.2.6",
    "@radix-ui/react-tabs": "^1.1.13",
    "@radix-ui/react-toggle": "^1.1.10",
    "@radix-ui/react-toggle-group": "^1.1.11",
    "@radix-ui/react-tooltip": "^1.2.8",
    "class-variance-authority": "^0.7.1",
    "clsx": "^2.1.1",
    "cmdk": "^1.1.1",
    "date-fns": "^4.1.0",
    "embla-carousel-react": "^8.6.0",
    "framer-motion": "^12.29.0",
    "input-otp": "^1.4.2",
    "lucide-react": "^0.562.0",
    "next": "16.1.1",
    "next-themes": "^0.4.6",
    "posthog-js": "^1.360.0",
    "react": "19.2.3",
    "react-day-picker": "^9.13.0",
    "react-dom": "19.2.3",
    "react-hook-form": "^7.71.1",
    "react-resizable-panels": "^4.4.1",
    "recharts": "^2.15.4",
    "sonner": "^2.0.7",
    "tailwind-merge": "^3.4.0",
    "vaul": "^1.1.2",
    "zod": "^4.3.5"
  },
  "devDependencies": {
    "@tailwindcss/postcss": "^4",
    "@types/node": "^20",
    "@types/react": "^19",
    "@types/react-dom": "^19",
    "eslint": "^9",
    "eslint-config-next": "16.1.1",
    "tailwindcss": "^4",
    "tw-animate-css": "^1.4.0",
    "typescript": "^5"
  }
}

ENDOFFILE

cat > 'tsconfig.json' << 'ENDOFFILE'
{
  "compilerOptions": {
    "target": "ES2017",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "react-jsx",
    "incremental": true,
    "plugins": [
      {
        "name": "next"
      }
    ],
    "paths": {
      "@/*": ["./*"]
    }
  },
  "include": [
    "next-env.d.ts",
    "**/*.ts",
    "**/*.tsx",
    ".next/types/**/*.ts",
    ".next/dev/types/**/*.ts",
    "**/*.mts"
  ],
  "exclude": ["node_modules"]
}

ENDOFFILE

cat > 'next.config.ts' << 'ENDOFFILE'
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  /* config options here */
  devIndicators: false
};

export default nextConfig;

ENDOFFILE

mkdir -p components
cat > 'components/root-metadata.tsx' << 'ENDOFFILE'
import { Metadata } from "next";

export const metadata: Metadata = {
  title: "TaskEval",
  description: "Task management and screenshot evaluation system with role-based dashboards",
  icons: {
    icon: "/codewords-asterisk.svg",
  },
  openGraph: {
    title: "TaskEval",
    description: "Task management and screenshot evaluation system with role-based dashboards",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "TaskEval",
    description: "Task management and screenshot evaluation system with role-based dashboards",
  },
};

ENDOFFILE


echo "All files created!"
echo "Now run: npm install && npm run dev"
