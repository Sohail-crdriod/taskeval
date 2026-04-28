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

