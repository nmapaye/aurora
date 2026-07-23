import React, { createRef } from 'react';
import {
  render,
  screen,
  userEvent,
} from '@testing-library/react-native';
import { StyleSheet, Text } from 'react-native';

import {
  SUMMARY_WALKTHROUGH_STEPS,
  SummaryWalkthroughCoach,
  WalkthroughReveal,
} from '~/features/summaryWalkthrough';

jest.mock('~/hooks/useAppScheme', () => ({
  __esModule: true,
  default: () => 'light',
}));

describe('Summary walkthrough presentation', () => {
  it('hides unrevealed content from touch and accessibility', async () => {
    await render(
      <WalkthroughReveal
        active
        revealed={false}
        reduceMotion={false}
        testID="walkthrough-reveal"
      >
        <Text>Hidden metric</Text>
      </WalkthroughReveal>,
    );

    const reveal = screen.getByTestId('walkthrough-reveal', {
      includeHiddenElements: true,
    });

    expect(reveal).toHaveProp(
      'accessibilityElementsHidden',
      true,
    );
    expect(reveal).toHaveProp(
      'importantForAccessibility',
      'no-hide-descendants',
    );
    expect(reveal).toHaveProp(
      'pointerEvents',
      'none',
    );
  });

  it('exposes approved coach copy and working actions', async () => {
    const onSkip = jest.fn();
    const onPrimary = jest.fn();
    const user = userEvent.setup();

    await render(
      <SummaryWalkthroughCoach
        step={SUMMARY_WALKTHROUGH_STEPS[0]}
        locked={false}
        headingRef={createRef()}
        onSkip={onSkip}
        onPrimary={onPrimary}
      />,
    );

    expect(
      screen.getByRole('header', { name: 'Your day at a glance' }),
    ).toBeOnTheScreen();
    expect(screen.getByText('1 of 4')).toBeOnTheScreen();
    await user.press(screen.getByRole('button', { name: 'Skip' }));
    await user.press(screen.getByRole('button', { name: 'Next' }));
    expect(onSkip).toHaveBeenCalledTimes(1);
    expect(onPrimary).toHaveBeenCalledTimes(1);
  });

  it('disables both actions while a transition is locked', async () => {
    await render(
      <SummaryWalkthroughCoach
        step={SUMMARY_WALKTHROUGH_STEPS[1]}
        locked
        headingRef={createRef()}
        onSkip={jest.fn()}
        onPrimary={jest.fn()}
      />,
    );

    expect(screen.getByRole('button', { name: 'Skip' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Next' })).toBeDisabled();
  });

  it('forwards coach layout measurements from its root', async () => {
    const onLayout = jest.fn();
    await render(
      <SummaryWalkthroughCoach
        step={SUMMARY_WALKTHROUGH_STEPS[0]}
        locked={false}
        headingRef={createRef()}
        onLayout={onLayout}
        onSkip={jest.fn()}
        onPrimary={jest.fn()}
      />,
    );
    const coachRoot = screen.root;
    expect(coachRoot).toHaveProp('onLayout', onLayout);
  });

  it('wraps large accessibility-size actions without shrinking touch targets', async () => {
    await render(
      <SummaryWalkthroughCoach
        step={SUMMARY_WALKTHROUGH_STEPS[3]}
        locked={false}
        headingRef={createRef()}
        onSkip={jest.fn()}
        onPrimary={jest.fn()}
      />,
    );

    const skip = screen.getByRole('button', { name: 'Skip' });
    const finish = screen.getByRole('button', { name: 'Finish' });
    const actions = skip.parent;

    expect(StyleSheet.flatten(actions?.props.style)).toMatchObject({
      flexDirection: 'row',
      flexWrap: 'wrap',
      justifyContent: 'flex-end',
    });
    expect(skip).toHaveStyle({ minHeight: 44 });
    expect(finish).toHaveStyle({ minHeight: 44 });
    expect(screen.getByText('Skip')).not.toHaveProp(
      'maxFontSizeMultiplier',
    );
    expect(screen.getByText('Finish')).not.toHaveProp(
      'maxFontSizeMultiplier',
    );
  });
});
