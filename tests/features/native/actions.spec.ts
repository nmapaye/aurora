import {
  enqueueNativeURL,
  pendingNativeAction,
  consumeNativeAction,
  clearNativeActions,
} from '~/features/native/actions';
import { jsonStringStorage } from '~/services/storage';
describe('durable native review queue', () => {
  beforeEach(clearNativeActions);
  it('keeps each action in order and rejects invalid payloads', () => {
    expect(enqueueNativeURL('aurora://native/log?amount=50', 'request-a')).toBe(
      true,
    );
    expect(enqueueNativeURL('aurora://native/log?amount=50', 'request-a')).toBe(
      true,
    );
    enqueueNativeURL('aurora://native/log?amount=70', 'request-b');
    expect(enqueueNativeURL('aurora://native/log?amount=0')).toBe(false);
    expect(pendingNativeAction()).toEqual({ kind: 'log', amount: 50 });
    consumeNativeAction();
    expect(pendingNativeAction()).toEqual({ kind: 'log', amount: 70 });
    expect(
      JSON.parse(jsonStringStorage.getItem('aurora/native-actions')!),
    ).toHaveLength(1);
    clearNativeActions();
    expect(pendingNativeAction()).toBeNull();
    expect(
      JSON.parse(jsonStringStorage.getItem('aurora/native-actions')!),
    ).toEqual([]);
  });
});
