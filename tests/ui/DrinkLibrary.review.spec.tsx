import React from 'react';
import { act, fireEvent, render, screen } from '@testing-library/react-native';
import { DrinkLibrary } from '~/features/caffeine/LoggingTools';
import { CAFFEINE_PRESETS } from '~/features/caffeine/presets';
import { defaultCaffeineState } from '~/features/caffeine/upgrades';
import { jsonStringStorage } from '~/services/storage';
import { useStore } from '~/state/store';

beforeEach(() => {
  useStore.setState({
    doses: [],
    doseUndo: null,
    caffeine: {
      ...defaultCaffeineState,
      drinks: [],
      favoriteIds: [...defaultCaffeineState.favoriteIds],
      draft: null,
      zeroDays: [],
    },
  });
});

it('edits, archives and restores a personal drink without changing the built-in presets', async () => {
  const originalPresets = JSON.parse(JSON.stringify(CAFFEINE_PRESETS));
  await render(<DrinkLibrary />);
  await fireEvent.changeText(
    screen.getByLabelText('Drink name'),
    'Kitchen coffee',
  );
  await fireEvent.changeText(
    screen.getByLabelText('Drink caffeine in mg'),
    '90',
  );
  await fireEvent.press(screen.getByRole('button', { name: 'Save drink' }));
  const id = useStore.getState().caffeine.drinks[0].id;
  await fireEvent.press(
    screen.getByRole('button', { name: 'Favorite Kitchen coffee' }),
  );
  await fireEvent.press(
    screen.getByRole('button', { name: 'Edit Kitchen coffee' }),
  );
  await fireEvent.changeText(
    screen.getByLabelText('Drink name'),
    'Weekend coffee',
  );
  await fireEvent.changeText(
    screen.getByLabelText('Drink caffeine in mg'),
    '75',
  );
  await fireEvent.press(screen.getByRole('button', { name: 'Save drink' }));
  expect(useStore.getState().caffeine.drinks).toEqual([
    { id, label: 'Weekend coffee', mg: 75, archived: false },
  ]);
  expect(screen.getByText('Weekend coffee · 75 mg')).toBeOnTheScreen();
  await fireEvent.press(
    screen.getByRole('button', { name: 'Archive Weekend coffee' }),
  );
  expect(screen.getByText('Weekend coffee · Archived')).toBeOnTheScreen();
  expect(useStore.getState().caffeine.favoriteIds).not.toContain(id);
  await fireEvent.press(
    screen.getByRole('button', { name: 'Restore Weekend coffee' }),
  );
  expect(screen.getByText('Weekend coffee · 75 mg')).toBeOnTheScreen();
  expect(CAFFEINE_PRESETS).toEqual(originalPresets);
});

it('persists favorite ordering and presents the new boundary controls after rehydration', async () => {
  await render(<DrinkLibrary />);
  await fireEvent.press(screen.getByRole('button', { name: 'Move Drip up' }));
  expect(screen.getByRole('button', { name: 'Move Drip up' })).toBeDisabled();
  expect(
    screen.getByRole('button', { name: 'Move Espresso up' }),
  ).not.toBeDisabled();
  const saved = jsonStringStorage.getItem('aurora/state');
  expect(saved).not.toBeNull();
  await act(() =>
    useStore.setState({
      caffeine: {
        ...defaultCaffeineState,
        favoriteIds: [...defaultCaffeineState.favoriteIds],
      },
    }),
  );
  jsonStringStorage.setItem('aurora/state', saved!);
  await act(async () => {
    await useStore.persist.rehydrate();
  });
  expect(useStore.getState().caffeine.favoriteIds).toEqual([
    'drip',
    'espresso',
    'matcha',
    'energy',
  ]);
  expect(screen.getByRole('button', { name: 'Move Drip up' })).toBeDisabled();
});
