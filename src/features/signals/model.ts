// One presentation contract for every signal module (Summary Pinned first,
// Sleep/Log/Insights later). A module names one signal, states where and when
// its value came from, says honestly whether it is an observation, a model
// estimate, sample data, or nothing yet, adds one line of context, and offers
// exactly one destination. Signals describe what was recorded; they never
// prescribe a dose or a sleep schedule.
export type SignalStatus = 'observed' | 'estimated' | 'sample' | 'empty';

export type SignalCardModel = {
  id: string;
  label: string;
  // When the value applies: "Today", "Yesterday", "Sep 24".
  period: string;
  // Where the value came from: "Manual", "Health", "Sample Data", ...
  source?: string;
  status: SignalStatus;
  // Omitted when status is 'empty'; an empty signal has no value to show.
  value?: string;
  context: string;
  // The one place this signal leads, e.g. "Open Sleep". The screen supplies
  // the navigation.
  destination: string;
};

// "Today · Manual", "Sep 24 · Health", "Today · Sample Data". Sample data is
// its own source label, so it needs no second status word.
export function signalMetaLine(model: SignalCardModel) {
  const statusLabel = model.status === 'estimated' ? 'Estimate' : undefined;
  return [model.period, model.source, statusLabel].filter(Boolean).join(' · ');
}

export function describeSignal(model: SignalCardModel) {
  const parts =
    model.status === 'empty'
      ? [model.label, 'No data', model.context]
      : [model.label, model.value, signalMetaLine(model), model.context];
  return parts.filter(Boolean).join(', ');
}

export function isSampleId(id: string) {
  return id.startsWith('demo:');
}

export function formatSignalDay(ts: number, now: number) {
  const day = new Date(ts);
  day.setHours(0, 0, 0, 0);
  const today = new Date(now);
  today.setHours(0, 0, 0, 0);
  const yesterday = new Date(today);
  yesterday.setDate(yesterday.getDate() - 1);
  if (day.getTime() === today.getTime()) return 'Today';
  if (day.getTime() === yesterday.getTime()) return 'Yesterday';
  try {
    return new Intl.DateTimeFormat(undefined, {
      month: 'short',
      day: 'numeric',
    }).format(new Date(ts));
  } catch {
    return new Date(ts).toDateString();
  }
}
