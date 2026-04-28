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

