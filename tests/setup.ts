const backingStore = new Map<string, string>();

beforeEach(() => {
  backingStore.clear();
});

jest.mock('react-native-mmkv', () => ({
  MMKV: class MockMMKV {
    getString(key: string) {
      return backingStore.get(key);
    }

    set(key: string, value: string) {
      backingStore.set(key, value);
    }

    delete(key: string) {
      backingStore.delete(key);
    }
  },
}));

jest.mock('react-native', () => ({
  Platform: { OS: 'ios' },
  PlatformColor: (value: string) => value,
}));

jest.mock('expo-modules-core', () => ({
  requireNativeModule: () => null,
}));
