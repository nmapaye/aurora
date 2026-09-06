import {
  enqueueNativeURL,
  clearNativeActions,
} from '~/features/native/actions';
import { jsonStringStorage } from '~/services/storage';

afterEach(() => {
  jest.restoreAllMocks();
  clearNativeActions();
});
it('does not acknowledge a retry until its request is durably saved after storage failure', () => {
  clearNativeActions();
  jest.spyOn(jsonStringStorage, 'setItem').mockImplementationOnce(() => {
    throw new Error('disk failure');
  });
  expect(() =>
    enqueueNativeURL('aurora://native/log?amount=95', 'retry-request'),
  ).toThrow();
  expect(
    enqueueNativeURL('aurora://native/log?amount=95', 'retry-request'),
  ).toBe(true);
  expect(
    JSON.parse(jsonStringStorage.getItem('aurora/native-actions')!),
  ).toEqual([
    { url: 'aurora://native/log?amount=95', requestId: 'retry-request' },
  ]);
});
it('recovers an unconfirmed action after module relaunch without touching intake history', () => {
  clearNativeActions();
  enqueueNativeURL('aurora://native/log?amount=60', 'relaunch-request');
  jest.isolateModules(() => {
    jest.doMock('~/services/storage', () => ({ jsonStringStorage }));
    const recovered = require('~/features/native/actions');
    expect(recovered.pendingNativeAction()).toEqual({
      kind: 'log',
      amount: 60,
    });
  });
});
