import cryptoFramework from '@ohos.security.cryptoFramework';
import util from '@ohos.util';
import { API_TOKEN_SECRET } from './ApiConfig';

function bytesToHex(bytes: Uint8Array): string {
  const hex: string[] = [];
  for (let index = 0; index < bytes.length; index++) {
    hex.push(bytes[index].toString(16).padStart(2, '0'));
  }
  return hex.join('').toLowerCase();
}

function utf8Bytes(value: string): Uint8Array {
  return new util.TextEncoder().encodeInto(value);
}

export async function md5(value: string): Promise<string> {
  const md = cryptoFramework.createMd('MD5');
  await md.update({ data: utf8Bytes(value) });
  const digest = await md.digest();
  return bytesToHex(digest.data);
}

export async function createApiToken(apiTs: number): Promise<string> {
  return md5(`${apiTs}${API_TOKEN_SECRET}`);
}

export function nowApiTs(): number {
  return Math.floor(Date.now() / 1000);
}

export async function aesEcbPkcs5DecryptBase64(base64CipherText: string, keyText: string): Promise<string> {
  const base64 = new util.Base64Helper();
  const encryptedBytes = base64.decodeSync(base64CipherText);
  const keyBytes = utf8Bytes(keyText);
  const symKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
  const key = await symKeyGenerator.convertKey({ data: keyBytes });
  const cipher = cryptoFramework.createCipher('AES256|ECB|PKCS5');
  await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, key, null);
  const decrypted = await cipher.doFinal({ data: encryptedBytes });
  return new util.TextDecoder().decodeWithStream(decrypted.data);
}
