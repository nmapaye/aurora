import { File, Paths } from 'expo-file-system';
import * as DocumentPicker from 'expo-document-picker';
import * as Sharing from 'expo-sharing';
import { parseBackup, type Backup } from '~/features/ownership/backup';
export async function shareBackupFile(backup: Backup) {
  if (!(await Sharing.isAvailableAsync()))
    throw new Error('System sharing is unavailable on this device.');
  const file = new File(Paths.cache, `aurora-backup-${backup.createdAt}.json`);
  try {
    file.create({ overwrite: true });
    file.write(JSON.stringify(backup, null, 2));
    await Sharing.shareAsync(file.uri, {
      mimeType: 'application/json',
      UTI: 'public.json',
      dialogTitle: 'Share unencrypted Aurora backup',
    });
  } finally {
    if (file.exists) file.delete();
  }
}
export async function pickBackupFile(): Promise<Backup | null> {
  const result = await DocumentPicker.getDocumentAsync({
    type: ['application/json', 'text/plain'],
    copyToCacheDirectory: true,
    multiple: false,
  });
  if (result.canceled) return null;
  const asset = result.assets[0];
  if (!asset) throw new Error('No file selected.');
  const file = new File(asset.uri);
  try {
    if (file.size > 20_000_000) throw new Error('Backup exceeds 20 MB.');
    return parseBackup(await file.text());
  } finally {
    if (file.uri.startsWith(Paths.cache.uri) && file.exists) file.delete();
  }
}
