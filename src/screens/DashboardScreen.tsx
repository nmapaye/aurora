import React, { useMemo, useRef } from 'react';
import type { LayoutChangeEvent } from 'react-native';
import { ScrollView, Text, View } from 'react-native';

import AlertnessRing from '~/components/AlertnessRing';
import AppIcon from '~/components/AppIcon';
import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import CaffeineTodayGraph from '~/components/CaffeineTodayGraph';
import SignalCard from '~/components/SignalCard';
import { Divider, Eyebrow, SectionHeader, Surface } from '~/components/ui';
import {
  estimateAlertness,
  formatSleepHours,
} from '~/features/summary/presentation';
import {
  caffeineLoggedSignal,
  reactionTestSignal,
  sleepSignal,
} from '~/features/summary/signals';
import {
  AppWalkthroughCoach,
  useAppWalkthrough,
  WalkthroughReveal,
} from '~/features/appWalkthrough';
import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
import useLargeText from '~/hooks/useLargeText';
import useNow from '~/hooks/useNow';
import { navigate } from '~/navigation';
import { useStore } from '~/state/store';
import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';
import { fontScaling, iconSizes, radii, spacing, typeRamp } from '~/theme/tokens';

export default function DashboardScreen() {
  const layout = useAdaptiveLayout();
  const largeText = useLargeText();
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  // Modeled values depend on the clock, not just stored data.
  const now = useNow();

  const doses = useStore((s) => s.doses);
  const sleeps = useStore((s) => s.sleeps);
  const prefs = useStore((s) => s.prefs);
  const vigilanceSessions = useStore((s) => s.vigilanceSessions);
  const demoMode = useStore((s) => s.demoMode);
  const loadDemoData = useStore((s) => s.loadDemoData);
  const clearDemoData = useStore((s) => s.clearDemoData);
  const scrollRef = useRef<ScrollView>(null);
  const contentRef = useRef<View>(null);
  const pinnedAnchorRef = useRef<View>(null);
  const sleepAnchorRef = useRef<View>(null);
  const caffeineAnchorRef = useRef<View>(null);

  const estimate = useMemo(
    () => estimateAlertness(now, doses, sleeps, prefs),
    [now, doses, sleeps, prefs],
  );

  const signals = useMemo(
    () => ({
      caffeine: caffeineLoggedSignal(doses, now),
      sleep: sleepSignal(sleeps, prefs.targetSleep, now),
      reaction: reactionTestSignal(vigilanceSessions, now),
    }),
    [doses, now, prefs.targetSleep, sleeps, vigilanceSessions],
  );

  const hasAnyData =
    doses.length > 0 || sleeps.length > 0 || vigilanceSessions.length > 0;

  // Sample data is always announced, but as a one-line status, not a card
  // louder than the real signals below it. A person with nothing recorded
  // yet gets a quiet offer to explore with it.
  const alertCard = demoMode ? (
    <View
      testID="summary-sample-status"
      style={{
        flexDirection: largeText ? 'column' : 'row',
        alignItems: largeText ? 'flex-start' : 'center',
        gap: spacing.xs,
      }}
    >
      <View
        style={{
          flex: largeText ? undefined : 1,
          alignSelf: largeText ? 'stretch' : undefined,
          flexDirection: 'row',
          alignItems: 'center',
          gap: spacing.xs,
        }}
      >
        <AppIcon
          name="sparkles-outline"
          size={iconSizes.row}
          color={palette.textSecondary}
        />
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{
            flex: 1,
            ...typeRamp.footnote,
            color: palette.textSecondary,
          }}
        >
          Showing sample data: example records, not yours.
        </Text>
      </View>
      <Button
        title="Clear Samples"
        accessibilityLabel="Clear Sample Data"
        variant="plain"
        onPress={clearDemoData}
      />
    </View>
  ) : !hasAnyData ? (
    <View
      style={{
        flexDirection: largeText ? 'column' : 'row',
        alignItems: largeText ? 'flex-start' : 'center',
        gap: spacing.xs,
      }}
    >
      <Text
        maxFontSizeMultiplier={fontScaling.body}
        style={{
          flex: largeText ? undefined : 1,
          ...typeRamp.footnote,
          color: palette.textSecondary,
        }}
      >
        Nothing recorded yet. You can explore with a labeled sample week.
      </Text>
      <Button
        title="Load Sample Data"
        variant="plain"
        onPress={loadDemoData}
      />
    </View>
  ) : null;

  const walkthrough = useAppWalkthrough({
    route: 'Summary',
    isWideLayout: layout.isWideLayout,
    scrollRef,
    contentRef,
  });

  const measurePinned = (_event: LayoutChangeEvent) => {
    walkthrough.measureAnchor('summary-pinned', pinnedAnchorRef.current);
    // The Caffeine and Sleep signals sit inside the pinned stack, so their own
    // onLayout does not fire when content above the stack moves them.
    walkthrough.measureAnchor('summary-caffeine', caffeineAnchorRef.current);
    walkthrough.measureAnchor('summary-sleep', sleepAnchorRef.current);
  };

  const measureCaffeine = (_event: LayoutChangeEvent) => {
    walkthrough.measureAnchor('summary-caffeine', caffeineAnchorRef.current);
  };

  const measureSleep = (_event: LayoutChangeEvent) => {
    walkthrough.measureAnchor('summary-sleep', sleepAnchorRef.current);
  };

  const revealedAlert = alertCard ? (
    <WalkthroughReveal
      active={walkthrough.active}
      revealed={walkthrough.isRevealed('summary-alert')}
      reduceMotion={walkthrough.reduceMotion}
      staggerIndex={2}
    >
      {alertCard}
    </WalkthroughReveal>
  ) : null;

  const pinnedSignals = [
    {
      key: 'caffeine',
      element: (
        // Summary's one way into Log, empty or populated; Log holds recent
        // entries and history. Step 3 of the walkthrough points here.
        <View
          ref={caffeineAnchorRef}
          collapsable={false}
          onLayout={measureCaffeine}
        >
          <SignalCard
            model={signals.caffeine}
            icon="cafe"
            accent={palette.caffeineAccent}
            onPress={() => navigate('Log')}
          />
        </View>
      ),
    },
    {
      key: 'sleep',
      element: (
        // Step 4 of the walkthrough points at this signal on its way to Sleep.
        <View ref={sleepAnchorRef} collapsable={false} onLayout={measureSleep}>
          <SignalCard
            model={signals.sleep}
            icon="bed"
            accent={palette.sleepAccent}
            onPress={() => navigate('Sleep')}
          />
        </View>
      ),
    },
    {
      key: 'reaction-test',
      element: (
        <SignalCard
          model={signals.reaction}
          icon="speedometer"
          accent={palette.vigilanceAccent}
          onPress={() => navigate('VigilanceTest')}
        />
      ),
    },
  ];

  const pinnedCards = (
    <>
      <WalkthroughReveal
        active={walkthrough.active}
        revealed={walkthrough.isRevealed('summary-pinned')}
        reduceMotion={walkthrough.reduceMotion}
        staggerIndex={0}
      >
        <SectionHeader prominence="prominent" title="Pinned" />
      </WalkthroughReveal>
      <View style={{ gap: spacing.md }}>
        {pinnedSignals.map((card, index) => (
          <WalkthroughReveal
            key={card.key}
            active={walkthrough.active}
            revealed={walkthrough.isRevealed('summary-pinned')}
            reduceMotion={walkthrough.reduceMotion}
            staggerIndex={index + 1}
          >
            {card.element}
          </WalkthroughReveal>
        ))}
      </View>
    </>
  );

  // Hero: Estimated Alertness from the existing model, paired with the
  // caffeine curve. Without recent sleep the ring shows no score. On iPhone
  // the ring and copy sit side by side so the curve starts on the first
  // screen; at large text sizes the copy moves below the ring and takes the
  // full width.
  const alertnessCopy =
    estimate.status === 'estimated'
      ? {
          title: `From ${formatSleepHours(estimate.sleepHours)} of sleep`,
          body: 'Plus active caffeine and time of day. Not a measurement.',
        }
      : {
          title: 'No recent sleep',
          body: 'Add sleep from the last 24 hours to see an estimate.',
        };

  const todayPanel = (
    <View style={{ gap: spacing.md }}>
      <SectionHeader
        prominence="prominent"
        title="Today"
        actionLabel="Details"
        onAction={() => navigate('Insights')}
      />
      <Surface
        radius={radii.hero}
        style={{
          padding: layout.isWideLayout ? spacing.lg : spacing.md,
          gap: layout.isWideLayout ? spacing.lg : spacing.md,
        }}
      >
        <View
          testID="summary-hero"
          style={{
            flexDirection: largeText ? 'column' : 'row',
            flexWrap: largeText ? 'nowrap' : 'wrap',
            alignItems: largeText ? 'stretch' : 'center',
            gap: layout.isWideLayout ? spacing.lg : spacing.md,
          }}
        >
          <AlertnessRing
            estimate={estimate}
            size={layout.isWideLayout ? 152 : 104}
          />
          <View
            style={
              largeText
                ? { gap: spacing.xxs }
                : { flex: 1, minWidth: 160, gap: spacing.xxs }
            }
          >
            <Eyebrow text="Estimated Alertness" />
            <Text
              maxFontSizeMultiplier={fontScaling.body}
              style={{
                ...(layout.isWideLayout ? typeRamp.title3 : typeRamp.headline),
                color: palette.textPrimary,
              }}
            >
              {alertnessCopy.title}
            </Text>
            <Text
              maxFontSizeMultiplier={fontScaling.body}
              style={{ ...typeRamp.footnote, color: palette.textSecondary }}
            >
              {alertnessCopy.body}
            </Text>
            {estimate.status === 'needs-sleep' ? (
              <Button
                title="Open Sleep"
                variant="tinted"
                onPress={() => navigate('Sleep')}
                style={{
                  alignSelf: 'flex-start',
                  marginTop: spacing.xs,
                  paddingVertical: spacing.xs,
                }}
              />
            ) : null}
          </View>
        </View>
        <Divider />
        <View style={{ gap: spacing.sm }}>
          <Eyebrow text="Caffeine Today" />
          <CaffeineTodayGraph
            height={layout.isWideLayout ? 240 : 160}
            cutoffHour={prefs.cutoffHour}
          />
        </View>
      </Surface>
    </View>
  );

  const revealedTodayPanel = (
    <WalkthroughReveal
      active={walkthrough.active}
      revealed={walkthrough.isRevealed('summary-today')}
      reduceMotion={walkthrough.reduceMotion}
      staggerIndex={1}
    >
      {todayPanel}
    </WalkthroughReveal>
  );

  const walkthroughCoach = walkthrough.active ? (
    <WalkthroughReveal
      key={walkthrough.step.id}
      active
      revealed={walkthrough.coachVisible}
      reduceMotion={walkthrough.reduceMotion}
    >
      <AppWalkthroughCoach
        step={walkthrough.step}
        locked={walkthrough.locked}
        headingRef={walkthrough.coachHeadingRef}
        onLayout={walkthrough.onCoachLayout}
        onSkip={walkthrough.onSkip}
        onPrimary={walkthrough.onPrimary}
      />
    </WalkthroughReveal>
  ) : null;

  const pinnedColumn = (
    <View
      ref={pinnedAnchorRef}
      collapsable={false}
      onLayout={measurePinned}
      style={{ gap: spacing.md }}
    >
      {pinnedCards}
    </View>
  );

  return (
    <AppScreen
      title="Summary"
      scrollRef={scrollRef}
      contentRef={contentRef}
      scrollEnabled={!walkthrough.active}
      interactionEnabled={!walkthrough.active}
      bottomOverlay={walkthroughCoach}
      onScroll={walkthrough.onScroll}
      onViewportLayout={walkthrough.onViewportLayout}
      headerTransform={(header) => (
        <WalkthroughReveal
          active={walkthrough.active}
          revealed={walkthrough.isRevealed('summary-header')}
          reduceMotion={walkthrough.reduceMotion}
          staggerIndex={0}
        >
          {header}
        </WalkthroughReveal>
      )}
    >
      {layout.isWideLayout ? (
        <View
          style={{
            flexDirection: 'row',
            alignItems: 'flex-start',
            gap: spacing.xl,
          }}
        >
          <View style={{ width: layout.leftColumnWidth, gap: spacing.md }}>
            {revealedTodayPanel}
            {revealedAlert}
          </View>
          <View style={{ width: layout.rightColumnWidth, gap: spacing.md }}>
            {pinnedColumn}
          </View>
        </View>
      ) : (
        <>
          {revealedTodayPanel}
          {revealedAlert}
          {pinnedColumn}
        </>
      )}
    </AppScreen>
  );
}
