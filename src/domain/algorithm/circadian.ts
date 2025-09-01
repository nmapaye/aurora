export function circadianC(nowMs: number, tz?: string){
  const d = new Date(nowMs);
  const localHour = Number(d.toLocaleString('en-US', { hour:'numeric', hour12:false, timeZone: tz }));
  return 0.5 - 0.5 * Math.cos(2*Math.PI * ((localHour - 3)/24));
}
  