export const mockDoses = [
  { id:'d1', timestamp: Date.now()-3*3600_000, mg: 95, source:'drip' },
  { id:'d2', timestamp: Date.now()-1*3600_000, mg: 60, source:'matcha' },
];
export const mockSleeps = [
  { id:'s1', start: Date.now()-9*3600_000, end: Date.now()-2*3600_000, type:'sleep' as const }
];
  