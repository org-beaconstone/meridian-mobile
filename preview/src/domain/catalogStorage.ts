import type { StoredCatalog } from './catalog';

function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function base64ToBytes(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

function storageKey(room: string, kind: 'key' | 'blob'): string {
  return `meridian.catalog.${room}.${kind}`;
}

async function roomKey(room: string): Promise<CryptoKey> {
  const existing = sessionStorage.getItem(storageKey(room, 'key'));
  if (existing) {
    return crypto.subtle.importKey('raw', base64ToBytes(existing), 'AES-GCM', false, ['encrypt', 'decrypt']);
  }
  const created = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, true, ['encrypt', 'decrypt']);
  const raw = new Uint8Array(await crypto.subtle.exportKey('raw', created));
  sessionStorage.setItem(storageKey(room, 'key'), bytesToBase64(raw));
  return created;
}

export async function readCatalogCache(room: string): Promise<StoredCatalog | null> {
  try {
    const blob = sessionStorage.getItem(storageKey(room, 'blob'));
    if (!blob) return null;
    const bytes = base64ToBytes(blob);
    const plain = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: bytes.slice(0, 12) },
      await roomKey(room),
      bytes.slice(12),
    );
    return JSON.parse(new TextDecoder().decode(plain)) as StoredCatalog;
  } catch {
    return null;
  }
}

export async function writeCatalogCache(room: string, stored: StoredCatalog): Promise<void> {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const encoded = new TextEncoder().encode(JSON.stringify(stored));
  const cipher = new Uint8Array(
    await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, await roomKey(room), encoded),
  );
  const blob = new Uint8Array(nonce.length + cipher.length);
  blob.set(nonce, 0);
  blob.set(cipher, nonce.length);
  sessionStorage.setItem(storageKey(room, 'blob'), bytesToBase64(blob));
}
