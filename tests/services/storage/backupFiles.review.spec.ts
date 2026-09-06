import { pickBackupFile, shareBackupFile } from '~/services/storage/backupFiles';
import { createBackup } from '~/features/ownership/backup';
import { useStore } from '~/state/store';

const mockFiles = new Map<string, { text: string; size: number }>();
const mockRead = jest.fn();
const mockPick = jest.fn();
const mockShare = jest.fn();
const mockAvailable = jest.fn();
jest.mock('expo-file-system', () => ({
  Paths: { cache: { uri: 'file:///cache/' } },
  File: class {
    uri: string;
    constructor(parent: string | { uri: string }, name?: string) { this.uri = (typeof parent === 'string' ? parent : parent.uri) + (name ?? ''); }
    get exists() { return mockFiles.has(this.uri); }
    get size() { return mockFiles.get(this.uri)?.size ?? 0; }
    create() { mockFiles.set(this.uri, { text: '', size: 0 }); }
    write(text: string) { mockFiles.set(this.uri, { text, size: text.length }); }
    async text() { mockRead(this.uri); return mockFiles.get(this.uri)?.text ?? ''; }
    delete() { mockFiles.delete(this.uri); }
  },
}), { virtual: true });
jest.mock('expo-document-picker', () => ({ getDocumentAsync: (...args: unknown[]) => mockPick(...args) }), { virtual: true });
jest.mock('expo-sharing', () => ({ isAvailableAsync: () => mockAvailable(), shareAsync: (...args: unknown[]) => mockShare(...args) }), { virtual: true });
beforeEach(() => { mockFiles.clear(); jest.clearAllMocks(); mockAvailable.mockResolvedValue(true); mockShare.mockResolvedValue(undefined); });
it('leaves files and current records untouched when the picker is canceled', async () => {
  mockFiles.set('file:///cache/unrelated', { text: 'keep', size: 4 });
  mockPick.mockResolvedValue({ canceled: true, assets: null });
  const doses = useStore.getState().doses;
  expect(await pickBackupFile()).toBeNull();
  expect(mockRead).not.toHaveBeenCalled();
  expect(mockFiles.has('file:///cache/unrelated')).toBe(true);
  expect(useStore.getState().doses).toBe(doses);
});
it('rejects an oversized picked copy before reading its contents', async () => {
  const uri = 'file:///cache/picked.json';
  mockFiles.set(uri, { text: '{}', size: 20000001 });
  mockPick.mockResolvedValue({ canceled: false, assets: [{ uri }] });
  await expect(pickBackupFile()).rejects.toThrow('20 MB');
  expect(mockRead).not.toHaveBeenCalled();
  expect(mockFiles.has(uri)).toBe(false);
});
it('cleans a malformed picked cache copy without changing app data', async () => {
  const uri = 'file:///cache/picked.json';
  mockFiles.set(uri, { text: '{bad', size: 4 });
  mockPick.mockResolvedValue({ canceled: false, assets: [{ uri }] });
  const doses = useStore.getState().doses;
  await expect(pickBackupFile()).rejects.toThrow('valid JSON');
  expect(mockFiles.has(uri)).toBe(false);
  expect(useStore.getState().doses).toBe(doses);
});
it('shares a JSON file with the unencrypted label and cleans it after a sharing failure', async () => {
  const backup = createBackup(useStore.getState(), 1700000000000);
  mockShare.mockImplementation(async (uri, options) => {
    expect(JSON.parse(mockFiles.get(uri)!.text)).toEqual(backup);
    expect(options.mimeType).toBe('application/json');
    expect(options.dialogTitle).toContain('unencrypted');
    throw new Error('Sharing failed');
  });
  await expect(shareBackupFile(backup)).rejects.toThrow('Sharing failed');
  expect(mockFiles.size).toBe(0);
});
