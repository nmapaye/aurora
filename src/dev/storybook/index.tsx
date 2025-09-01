import React, { useEffect, useState } from 'react';
import { View, Text, ActivityIndicator } from 'react-native';

type StorybookComponent = React.ComponentType<any>;

// Attempt to require known stories. Wrap each in try/catch so missing files don't break bundling.
function loadStories() {
  try { require('./stories/AlertnessRing.stories'); } catch {}
  try { require('./stories/TimelineGraph.stories'); } catch {}
  try { require('./stories/Chip.stories'); } catch {}
  try { require('./stories/EmptyState.stories'); } catch {}
  // Add more lines here as you create new *.stories.tsx files.
}

/**
 * Storybook host component.
 * - Only activates if EXPO_PUBLIC_STORYBOOK=1
 * - Dynamically imports @storybook/react-native to avoid hard dependency for prod builds
 * - Shows a friendly message if Storybook is disabled or missing
 */
export default function StorybookUIRoot() {
  const [UI, setUI] = useState<StorybookComponent | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const enabled = process.env.EXPO_PUBLIC_STORYBOOK === '1';
    if (!enabled) {
      setError('Storybook disabled. Set EXPO_PUBLIC_STORYBOOK=1 to enable.');
      return;
    }
    (async () => {
      try {
        // Dynamic import avoids bundling errors if not installed
        // eslint-disable-next-line @typescript-eslint/no-var-requires
        const sb: any = await import('@storybook/react-native');
        const { getStorybookUI, configure } = sb;
        configure(loadStories);
        const UIComp = getStorybookUI({});
        setUI(() => UIComp);
      } catch (e: any) {
        setError(`Failed to load Storybook: ${e?.message ?? e}`);
      }
    })();
  }, []);

  if (UI) {
    const Comp = UI;
    return <Comp />;
  }

  return (
    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24 }}>
      {error ? (
        <>
          <Text style={{ color: 'white', fontSize: 16, textAlign: 'center' }}>{error}</Text>
          <Text style={{ color: 'rgba(255,255,255,0.7)', textAlign: 'center', marginTop: 8 }}>
            Install Storybook and run with:
            {'\n'}npm i -D @storybook/react-native @storybook/addons
            {'\n'}EXPO_PUBLIC_STORYBOOK=1 npx expo start
          </Text>
        </>
      ) : (
        <>
          <ActivityIndicator />
          <Text style={{ color: 'rgba(255,255,255,0.7)', marginTop: 8 }}>Loading Storybook…</Text>
        </>
      )}
    </View>
  );
}