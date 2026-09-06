import { parseNativeAction } from '~/features/native/model';

it('accepts native links with the actual React Native URL implementation installed', () => {
  const RuntimeURL = require('react-native/Libraries/Blob/URL').URL;
  const original = global.URL;
  try {
    global.URL = RuntimeURL;
    expect(parseNativeAction('aurora://native/log?amount=95')).toEqual({ kind: 'log', amount: 95 });
    expect(parseNativeAction('aurora://native/log?drinkId=personal%3Atea')).toEqual({ kind: 'log', drinkId: 'personal:tea' });
    expect(parseNativeAction('aurora://native/nap')).toEqual({ kind: 'nap' });
  } finally {
    global.URL = original;
  }
});
