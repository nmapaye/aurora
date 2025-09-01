export function totalSleepHoursLast24(nowMs: number, sleeps: {start:number; end:number}[]){
  const from = nowMs - 24*3600_000;
  let total = 0;
  for(const s of sleeps){
    const start = Math.max(s.start, from);
    const end = Math.min(s.end, nowMs);
    if(end > start) total += (end-start)/3600_000;
  }
  return total;
}
export function sleepDebt(nowMs: number, sleeps: any[], targetH: number){
  const H = totalSleepHoursLast24(nowMs, sleeps);
  const debt = (targetH - H)/targetH;
  return Math.max(0, Math.min(1, debt));
}
  