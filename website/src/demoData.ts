export type DemoMode = 'healthkit' | 'manual';

export type DemoDose = {
  label: string;
  mg: number;
  time: string;
};

export type DemoVigilanceResult = {
  score: number;
  rating: string;
  medianReactionMs: number;
  lapseCount: number;
  falseStartCount: number;
  validTaps: string;
  completedAt: string;
};

export type DemoHistoryRow = {
  title: string;
  subtitle: string;
  detail: string;
};

export type DemoScenario = {
  id: DemoMode;
  modeLabel: string;
  heroLine: string;
  todayCaffeineMg: number;
  activeCaffeineMg: number;
  alertnessScore: number;
  cutoffTime: string;
  bedtime: string;
  wakeTime: string;
  sleepStatus: string;
  sleepSummary: string;
  sleepDetail: string;
  plan: Array<{ label: string; mg: number; time: string }>;
  latestVigilance: DemoVigilanceResult;
  daypartMix: Array<{ label: string; pct: number; mg: number }>;
  sourceMix: Array<{ label: string; pct: number; mg: number }>;
  trend: number[];
  doses: DemoDose[];
  history: DemoHistoryRow[];
};

export const demoScenarios: Record<DemoMode, DemoScenario> = {
  healthkit: {
    id: 'healthkit',
    modeLabel: 'With Health data',
    heroLine:
      'Sleep from Health helps Aurora shape a clearer cutoff, a steadier plan, and a more grounded daily view.',
    todayCaffeineMg: 185,
    activeCaffeineMg: 82,
    alertnessScore: 74,
    cutoffTime: '2:10 PM',
    bedtime: '10:35 PM',
    wakeTime: '6:35 AM',
    sleepStatus: 'Connected to Health',
    sleepSummary: '7h 42m imported from last night',
    sleepDetail: 'Wake time 6:48 AM • the latest dose usually lands about 228 min before sleep',
    plan: [
      { label: 'Kickstart', mg: 80, time: '7:20 AM' },
      { label: 'Sustain', mg: 80, time: '10:50 AM' },
      { label: 'Top-up', mg: 40, time: '1:40 PM' },
    ],
    latestVigilance: {
      score: 78,
      rating: 'Steady',
      medianReactionMs: 284,
      lapseCount: 1,
      falseStartCount: 0,
      validTaps: '11 / 12',
      completedAt: 'Today, 1:18 PM',
    },
    daypartMix: [
      { label: '05–11', pct: 58, mg: 108 },
      { label: '11–17', pct: 42, mg: 77 },
      { label: '17–21', pct: 0, mg: 0 },
      { label: '21–05', pct: 0, mg: 0 },
    ],
    sourceMix: [
      { label: 'Coffee', pct: 69, mg: 128 },
      { label: 'Tea', pct: 17, mg: 32 },
      { label: 'Energy', pct: 14, mg: 25 },
    ],
    trend: [140, 180, 165, 210, 175, 195, 185],
    doses: [
      { label: 'Drip coffee', mg: 95, time: '7:34 AM' },
      { label: 'Matcha', mg: 70, time: '10:58 AM' },
      { label: 'Espresso', mg: 20, time: '1:05 PM' },
    ],
    history: [
      { title: '78 Steady', subtitle: 'Median 284 ms • 1 lapse', detail: 'Today, 1:18 PM' },
      { title: '95 mg • Drip', subtitle: 'First cup of the day', detail: 'Today, 7:34 AM' },
      { title: '70 mg • Matcha', subtitle: 'Late-morning boost', detail: 'Today, 10:58 AM' },
    ],
  },
  manual: {
    id: 'manual',
    modeLabel: 'Manual only',
    heroLine:
      'Aurora still works well without Health by keeping logging fast and guidance easy to follow through the day.',
    todayCaffeineMg: 130,
    activeCaffeineMg: 49,
    alertnessScore: 67,
    cutoffTime: '1:40 PM',
    bedtime: '10:20 PM',
    wakeTime: '6:20 AM',
    sleepStatus: 'Manual logging only',
    sleepSummary: 'No sleep import connected yet',
    sleepDetail: 'Aurora falls back to your configured sleep target and current intake.',
    plan: [
      { label: 'Kickstart', mg: 60, time: '7:30 AM' },
      { label: 'Sustain', mg: 60, time: '11:00 AM' },
    ],
    latestVigilance: {
      score: 71,
      rating: 'Steady',
      medianReactionMs: 301,
      lapseCount: 2,
      falseStartCount: 1,
      validTaps: '10 / 12',
      completedAt: 'Today, 12:42 PM',
    },
    daypartMix: [
      { label: '05–11', pct: 46, mg: 60 },
      { label: '11–17', pct: 54, mg: 70 },
      { label: '17–21', pct: 0, mg: 0 },
      { label: '21–05', pct: 0, mg: 0 },
    ],
    sourceMix: [
      { label: 'Coffee', pct: 46, mg: 60 },
      { label: 'Tea', pct: 54, mg: 70 },
    ],
    trend: [110, 125, 90, 140, 120, 135, 130],
    doses: [
      { label: 'Espresso', mg: 60, time: '8:02 AM' },
      { label: 'Matcha', mg: 70, time: '11:27 AM' },
    ],
    history: [
      { title: '71 Steady', subtitle: 'Median 301 ms • 1 false start', detail: 'Today, 12:42 PM' },
      { title: '60 mg • Espresso', subtitle: 'Logged from a quick add', detail: 'Today, 8:02 AM' },
      { title: '70 mg • Matcha', subtitle: 'Logged as a custom entry', detail: 'Today, 11:27 AM' },
    ],
  },
};

export const siteSections = [
  {
    title: 'Clearer caffeine timing',
    body:
      'Aurora turns your intake and sleep context into a clearer cutoff, a bedtime signal, and a steadier pacing plan.',
  },
  {
    title: 'Fast enough to keep using',
    body:
      'Quick presets and custom entries keep logging light enough to use throughout the day without breaking your flow.',
  },
  {
    title: 'A short attentiveness check',
    body:
      'A 60-second reaction test gives people a repeatable read on attentiveness without sending personal data to a server.',
  },
  {
    title: 'Private by design',
    body:
      'Aurora is built to stay useful on-device, with Health support on iPhone and no cloud account required.',
  },
];
