import React from 'react';
import { render, screen, fireEvent, act } from '@testing-library/react-native';
import {
  DrinkLibrary,
  ServingCalculator,
  DosePreview,
  DoseUndoNotice,
} from '~/features/caffeine/LoggingTools';
import { useStore } from '~/state/store';
import { defaultCaffeineState } from '~/features/caffeine/upgrades';
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));
const now = new Date(2026, 8, 7, 12).getTime();
beforeEach(() => {
  jest.spyOn(Date, 'now').mockReturnValue(now);
  useStore.setState({
    doses: [],
    doseUndo: null,
    caffeine: { ...defaultCaffeineState, drinks: [], draft: null },
    onboarding: {
      ...useStore.getState().onboarding,
      completed: true,
      appWalkthroughCompleted: true,
    },
  });
});
afterEach(() => jest.restoreAllMocks());
it('creates a personal drink and selects it as a favorite', async () => {
  await render(<DrinkLibrary />);
  await fireEvent.changeText(screen.getByLabelText('Drink name'), 'Home brew');
  await fireEvent.changeText(
    screen.getByLabelText('Drink caffeine in mg'),
    '110',
  );
  await fireEvent.press(screen.getByRole('button', { name: 'Save drink' }));
  await fireEvent.press(
    screen.getByRole('button', { name: 'Favorite Home brew' }),
  );
  expect(useStore.getState().caffeine.favoriteIds).toHaveLength(5);
});
it('shows the concentration calculation and applies it to a draft', async () => {
  const onApply = jest.fn();
  await render(<ServingCalculator onApply={onApply} />);
  await fireEvent.press(screen.getByText('Label volume'));
  await fireEvent.changeText(
    screen.getByLabelText('Label caffeine in mg'),
    '32',
  );
  await fireEvent.changeText(
    screen.getByLabelText('Consumed volume in ml'),
    '250',
  );
  await fireEvent.press(screen.getByRole('button', { name: 'Use 80 mg' }));
  expect(onApply).toHaveBeenCalledWith(80);
});
it('renders a preview and a working undo action', async () => {
  await render(
    <>
      <DosePreview
        draft={{ mg: '100', source: 'Coffee', timestamp: now, note: '' }}
      />
      <DoseUndoNotice />
    </>,
  );
  expect(screen.getByText(/100 mg on/)).toBeOnTheScreen();
  await act(() =>
    useStore.getState().addDose({ id: 'new', timestamp: now, mg: 100 }),
  );
  await fireEvent.press(
    screen.getByRole('button', { name: 'Undo caffeine change' }),
  );
  expect(useStore.getState().doses).toEqual([]);
});
