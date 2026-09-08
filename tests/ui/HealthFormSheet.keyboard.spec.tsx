import React from 'react';
import { TextInput } from 'react-native';
import { render, screen, fireEvent } from '@testing-library/react-native';
import { HealthFormSheet } from '~/components/health/HealthFormSheet';
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 24, right: 0, bottom: 34, left: 0 }),
}));
it('keeps Save in keyboard-avoiding scroll content with safe-area padding', async () => {
  const save = jest.fn();
  await render(<HealthFormSheet visible title="Add sleep" onCancel={jest.fn()} onSave={save}>
    <TextInput accessibilityLabel="Notes" />
  </HealthFormSheet>);
  expect(screen.getByTestId('health-form-keyboard')).toHaveStyle({ flex: 1, paddingTop: 24 });
  const scroll = screen.getByTestId('health-form-scroll');
  expect(scroll.props.keyboardShouldPersistTaps).toBe('handled');
  expect(scroll.props.contentContainerStyle.paddingBottom).toBeGreaterThanOrEqual(34);
  await fireEvent.changeText(screen.getByLabelText('Notes'), 'Sleep notes');
  await fireEvent.press(screen.getByRole('button', { name: 'Save' }));
  expect(save).toHaveBeenCalledTimes(1);
});
