import React, { useState } from 'react';
import { View } from 'react-native';
import Button from '~/components/Button';
import { PlanningText } from '~/features/planning/components';
export const metricExplanations = {
  sleepSession: {
    title: 'latest sleep session',
    text: 'The Summary Sleep card shows the duration between the start and end of the latest stored sleep session, in hours and minutes. It is a single record, which can be main sleep, a nap, or labeled sample data. It does not combine separate segments or remove overlap with other records. No Data means there is no session available. Open Sleep for episode totals and overlap review.',
  },
  scenarioCaffeine: {
    title: 'scenario caffeine inputs',
    text: 'Scenario projections combine personal logged doses through now with the hypothetical doses in the selected scenario. Hypothetical amounts and minute offsets become future dose times for the calculation only; they are not added to intake history. All doses use exponential decay with your active half-life, except the sensitivity comparison which uses its displayed half-lives. Results are mg estimates, not measurements. Unlogged intake is absent; empty inputs are not proof of zero intake.',
  },
  cutoff: {
    title: 'caffeine cutoff and sleep times',
    text: 'Cutoff is the next occurrence of your chosen local cutoff hour. It is a reminder preference, not a calculated safe-dose or safe-sleep boundary. Bedtime and wake time use your weekly sleep schedule with date exceptions; sleep times may cross midnight. Caffeine at bedtime is a model estimate using recorded amounts, times, and your half-life preference, and misses unlogged intake.',
  },
  caffeine: {
    title: 'modeled caffeine',
    text: 'Estimated caffeine remaining, in mg, uses logged dose amounts and times with your half-life preference and exponential decay. It does not measure blood caffeine or account for individual absorption. Unlogged intake is absent. An estimate of 0 with no records means no modeled input, not confirmed zero intake. Sample records are excluded in personal analysis.',
  },
  alertness: {
    title: 'modeled alertness',
    text: 'A model score from 0 to 100 combines time-of-day circadian rhythm, modeled caffeine effect, sleep recorded in the preceding 24 hours, your sleep target, and inertia after recorded waking. It is not a reaction-test score or a clinical measure. Missing sleep is not proof of no sleep, and can lower the estimate. Historical inspection uses only sleep completed by that time. Future values assume no additional unlogged doses or sleep.',
  },
  sleep: {
    title: 'recorded sleep',
    text: 'Recorded sleep duration is in hours. Overlapping intervals count once; brief gaps within an episode remain excluded. Daily totals include main sleep and naps on the wake date. Missing dates are omitted from averages, never assigned zero hours. Main sleep alone is used for the sleep-onset caffeine plot. Records may be incomplete and do not measure sleep quality.',
  },
  weekday: {
    title: 'weekday averages',
    text: 'Each weekday compares its recorded daily caffeine total in mg and sleep duration in hours. Caffeine averages include explicitly confirmed caffeine-free days as zero. Missing days are excluded separately for each measure, so their counts can differ. Sleep belongs to its wake date. The selected range includes today so far, and sample data is excluded.',
  },
  bedtime: {
    title: 'sleep-onset comparison',
    text: 'Each point pairs modeled caffeine in mg at recorded main-sleep onset with that episode’s recorded duration in hours. At least one dose in the preceding 24 hours or a confirmed zero on the onset date is required. All preceding personal doses contribute decay. This is incomplete intake coverage, not proof that every dose was logged. Overlaps count once. At least 5 points are needed for an average summary. Timing, health, work, and many other factors can differ; this descriptive plot cannot establish a caffeine effect or cause.',
  },
  vigilance: {
    title: 'vigilance metrics',
    text: 'Reaction times are in milliseconds (ms); lower is a faster response. Median, mean, and reaction variation (standard deviation) describe valid responses; fastest is the shortest valid reaction. Lapses include responses at least 500 ms and missed cues; false starts are taps before a cue or faster than 150 ms. The test score is a separate 0–100 summary of task performance, not the modeled alertness score. Missing reaction metrics remain unavailable rather than zero.',
  },
  baseline: {
    title: 'personal test baseline',
    text: 'The baseline is the median of reaction-time medians from at least 3 earlier completed personal tests with valid reactions. The selected test, tests completed at the same time or later, sample tests, and tests without a reaction median are excluded. A negative difference means a faster median than this baseline. Counts describe the available records, not statistical certainty.',
  },
  pairing: {
    title: 'check-in and test pairing',
    text: 'Each 1–5 subjective check-in is paired with the nearest completed personal test within 30 minutes of its completion time, inclusive. Equal distances use the earlier completion, then the test ID. A test can appear with multiple check-ins. Rating and reaction-time ms remain separate scales; no combined score or correlation is inferred. At least 5 pairs with reaction medians are needed for a descriptive summary. Missing or unpaired observations are excluded from that summary.',
  },
  completeness: {
    title: 'data completeness',
    text: 'Caffeine recorded means at least one personal entry; confirmed zero means you explicitly marked a caffeine-free day. Otherwise intake is missing. Sleep means a completed personal episode with a wake date on that day. Test and check-in counts refer to their completion or record date. These flags confirm records exist, not that a day is fully captured. Sample data and future entries are excluded.',
  },
  weekly: {
    title: 'weekly review',
    text: 'This on-device review compares the last 7 calendar days, including today so far, with the preceding 7. Changes compare means of recorded days and show both counts. Missing caffeine or sleep is excluded, so changes may reflect unequal coverage. Target progress uses your daily caffeine limit and sleep-hours target, not a recommended dose. Sample data is excluded; no causal or clinical conclusion is produced.',
  },
  adherence: {
    title: 'caffeine target adherence',
    text: 'The percentage describes recorded days at or below your chosen daily caffeine limit in mg, including confirmed caffeine-free days. Missing days do not count as success and break a consecutive-day streak. A personal target is not a safe-dose threshold. This measure describes logged amounts only.',
  },
} as const;
export type MetricKey = keyof typeof metricExplanations;
export default function MetricExplanation({ metric }: { metric: MetricKey }) {
  const [expanded, setExpanded] = useState(false),
    content = metricExplanations[metric];
  return (
    <View>
      <Button
        title={`${expanded ? 'Hide explanation of' : 'Explain'} ${content.title}`}
        variant="plain"
        accessibilityValue={{ text: expanded ? 'Expanded' : 'Collapsed' }}
        onPress={() => setExpanded(!expanded)}
      />
      {expanded ? <PlanningText>{content.text}</PlanningText> : null}
    </View>
  );
}
