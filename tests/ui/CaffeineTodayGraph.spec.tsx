import React from 'react';
import {
  act,
  fireEvent,
  render,
  screen,
  userEvent,
} from '@testing-library/react-native';

import CaffeineTodayGraph from '~/components/CaffeineTodayGraph';
import useLargeText from '~/hooks/useLargeText';
import { useStore } from '~/state/store';

jest.mock('~/hooks/useLargeText', () => ({
  __esModule: true,
  default: jest.fn(() => false),
}));

describe('CaffeineTodayGraph readout layout', () => {
  beforeEach(() => {
    useStore.setState({ doses: [], sleeps: [] });
  });

  it('keeps readout values side by side at standard text sizes', async () => {
    jest.mocked(useLargeText).mockReturnValue(false);
    await render(<CaffeineTodayGraph />);
    expect(screen.getByTestId('caffeine-readout-values')).toHaveStyle({
      flexDirection: 'row',
      flexWrap: 'wrap',
    });
  });

  it('stacks readout values at large text so each wraps at full width', async () => {
    jest.mocked(useLargeText).mockReturnValue(true);
    await render(<CaffeineTodayGraph />);
    expect(screen.getByTestId('caffeine-readout-values')).toHaveStyle({
      flexDirection: 'column',
    });
    expect(screen.getByText('Active caffeine')).toBeOnTheScreen();
    expect(screen.getByText('Needs recent sleep')).toBeOnTheScreen();
  });
});

// Scrub targets are fixed x positions, so pin the clock to mid-afternoon:
// early in the morning those times would still be in the future.
function pinClockToAfternoon() {
  const afternoon = new Date();
  afternoon.setHours(15, 0, 0, 0);
  jest.spyOn(Date, 'now').mockReturnValue(afternoon.getTime());
}

describe('CaffeineTodayGraph inspection', () => {
  beforeEach(() => {
    pinClockToAfternoon();
    useStore.setState({ doses: [], sleeps: [] });
  });
  afterEach(() => jest.restoreAllMocks());

  async function renderLaidOut() {
    await render(<CaffeineTodayGraph />);
    const graph = screen.getByTestId('caffeine-today-graph');
    await fireEvent(graph, 'layout', {
      nativeEvent: { layout: { x: 0, y: 0, width: 320, height: 200 } },
    });
    return graph;
  }

  it('summarizes the chart honestly and defaults the readout to now', async () => {
    const graph = await renderLaidOut();

    expect(graph).toHaveProp('accessibilityRole', 'adjustable');
    expect(graph.props.accessibilityLabel).toBe(
      'Active caffeine today chart. No caffeine logged today. Modeled active caffeine stays at 0 milligrams.',
    );
    expect(graph.props.accessibilityValue.text).toMatch(
      /^Now, .*no doses logged today by then, alertness needs recent sleep\.$/,
    );
    expect(screen.getByText(/^Now · /)).toBeOnTheScreen();
    expect(screen.getByText('Needs recent sleep')).toBeOnTheScreen();
    expect(
      screen.queryByRole('button', { name: 'Return to now' }),
    ).not.toBeOnTheScreen();
  });

  it('moves the selection with VoiceOver adjust actions and returns to now', async () => {
    const user = userEvent.setup();
    const graph = await renderLaidOut();

    await fireEvent(graph, 'accessibilityAction', {
      nativeEvent: { actionName: 'decrement' },
    });

    expect(graph.props.accessibilityValue.text).not.toMatch(/^Now, /);
    expect(screen.queryByText(/^Now · /)).not.toBeOnTheScreen();

    await user.press(screen.getByRole('button', { name: 'Return to now' }));
    expect(screen.getByText(/^Now · /)).toBeOnTheScreen();
  });
});

// Drives the chart's real PanResponder handlers with a single-finger touch
// history, the same shape the RN responder system hands them.
function touchDriver(graph: ReturnType<typeof screen.getByTestId>) {
  let timestamp = 1;
  let previous = { x: 0, y: 0 };
  const event = (x: number, y: number) => {
    timestamp += 16;
    const touch = {
      touchActive: true,
      startPageX: previous.x,
      startPageY: previous.y,
      startTimeStamp: timestamp - 16,
      currentPageX: x,
      currentPageY: y,
      currentTimeStamp: timestamp,
      previousPageX: previous.x,
      previousPageY: previous.y,
      previousTimeStamp: timestamp - 16,
    };
    previous = { x, y };
    return {
      nativeEvent: { locationX: x, locationY: y, pageX: x, pageY: y },
      touchHistory: {
        numberActiveTouches: 1,
        indexOfSingleActiveTouch: 0,
        mostRecentTimeStamp: timestamp,
        touchBank: [touch],
      },
    };
  };
  const handlers = () => graph.props;
  return {
    start(x: number, y: number) {
      previous = { x, y };
      const e = event(x, y);
      const claims: boolean = handlers().onStartShouldSetResponder(e);
      const blocksNative: boolean = handlers().onResponderGrant(e);
      return { claims, blocksNative };
    },
    async move(x: number, y: number) {
      await act(async () => {
        handlers().onResponderMove(event(x, y));
      });
    },
    yieldsToScroll() {
      return handlers().onResponderTerminationRequest(
        event(previous.x, previous.y),
      );
    },
    async release() {
      await act(async () => {
        handlers().onResponderRelease(event(previous.x, previous.y));
      });
    },
  };
}

describe('CaffeineTodayGraph gesture arbitration', () => {
  beforeEach(() => {
    pinClockToAfternoon();
    useStore.setState({ doses: [], sleeps: [] });
  });
  afterEach(() => jest.restoreAllMocks());

  async function renderLaidOut() {
    await render(<CaffeineTodayGraph />);
    const graph = screen.getByTestId('caffeine-today-graph');
    await fireEvent(graph, 'layout', {
      nativeEvent: { layout: { x: 0, y: 0, width: 320, height: 200 } },
    });
    return touchDriver(screen.getByTestId('caffeine-today-graph'));
  }

  const returnToNow = () =>
    screen.queryByRole('button', { name: 'Return to now' });

  it('lets a vertical swipe scroll the page without selecting, even if it drifts sideways', async () => {
    const touch = await renderLaidOut();

    const { claims, blocksNative } = touch.start(160, 60);
    expect(claims).toBe(true);
    expect(blocksNative).toBe(false);
    expect(touch.yieldsToScroll()).toBe(true);

    await touch.move(162, 90);
    await touch.move(163, 140);
    expect(touch.yieldsToScroll()).toBe(true);
    await touch.move(260, 150);
    expect(touch.yieldsToScroll()).toBe(true);
    await touch.release();

    expect(returnToNow()).not.toBeOnTheScreen();
    expect(screen.getByText(/^Now · /)).toBeOnTheScreen();
  });

  it('scrubs on a horizontal drag and holds the gesture against scrolling', async () => {
    const touch = await renderLaidOut();

    touch.start(60, 80);
    await touch.move(90, 82);
    expect(touch.yieldsToScroll()).toBe(false);
    await touch.move(100, 84);
    await touch.release();

    expect(returnToNow()).toBeOnTheScreen();
    expect(screen.queryByText(/^Now · /)).not.toBeOnTheScreen();
  });

  it('selects the tapped time on a tap', async () => {
    const touch = await renderLaidOut();

    touch.start(60, 80);
    await touch.move(62, 81);
    await touch.release();

    expect(returnToNow()).toBeOnTheScreen();
    expect(screen.queryByText(/^Now · /)).not.toBeOnTheScreen();
  });
});
