function mgActive(nowMs: number, doses: { timestamp:number; mg:number }[], halfLifeH: number){
  const hlMs = halfLifeH * 3600_000;
  return doses.filter(d => d.timestamp <= nowMs).reduce((acc,d)=>{
    const dt = nowMs - d.timestamp;
    const factor = Math.pow(0.5, dt/hlMs);
    return acc + d.mg * factor;
  },0);
}
export function mgActiveEffect(nowMs: number, doses: any[], halfLifeH: number){
  const mg = mgActive(nowMs, doses, halfLifeH);
  const E = 1 - Math.exp(-mg/100);
  return E;
}
export { mgActive };
  