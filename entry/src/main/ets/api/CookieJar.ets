export interface StoredCookie {
  name: string;
  value: string;
  domain?: string;
  path?: string;
  expires?: number;
}

export class CookieJar {
  private cookies: Map<string, StoredCookie> = new Map();

  loadHeader(): string {
    const values: string[] = [];
    this.cookies.forEach((cookie: StoredCookie) => {
      if (cookie.expires !== undefined && cookie.expires > 0 && cookie.expires < Date.now()) {
        return;
      }
      values.push(`${cookie.name}=${cookie.value}`);
    });
    return values.join('; ');
  }

  saveFromSetCookie(setCookieHeaders: string[] | undefined): void {
    if (!setCookieHeaders) {
      return;
    }
    setCookieHeaders.forEach((header: string) => this.saveOne(header));
  }

  snapshot(): StoredCookie[] {
    return Array.from(this.cookies.values());
  }

  restore(cookies: StoredCookie[]): void {
    this.cookies.clear();
    cookies.forEach((cookie: StoredCookie) => {
      this.cookies.set(this.keyOf(cookie), cookie);
    });
  }

  clear(): void {
    this.cookies.clear();
  }

  private saveOne(header: string): void {
    const parts = header.split(';').map((part: string) => part.trim());
    const first = parts[0];
    const eq = first.indexOf('=');
    if (eq <= 0) {
      return;
    }

    const cookie: StoredCookie = {
      name: first.slice(0, eq),
      value: first.slice(eq + 1),
      path: '/'
    };

    for (let index = 1; index < parts.length; index++) {
      const item = parts[index];
      const attrEq = item.indexOf('=');
      const key = (attrEq >= 0 ? item.slice(0, attrEq) : item).toLowerCase();
      const value = attrEq >= 0 ? item.slice(attrEq + 1) : '';
      if (key === 'domain') {
        cookie.domain = value;
      } else if (key === 'path') {
        cookie.path = value;
      } else if (key === 'expires') {
        const expires = Date.parse(value);
        if (!Number.isNaN(expires)) {
          cookie.expires = expires;
        }
      } else if (key === 'max-age') {
        const seconds = Number.parseInt(value, 10);
        if (!Number.isNaN(seconds)) {
          cookie.expires = Date.now() + seconds * 1000;
        }
      }
    }

    this.cookies.set(this.keyOf(cookie), cookie);
  }

  private keyOf(cookie: StoredCookie): string {
    return `${cookie.domain ?? ''}:${cookie.path ?? '/'}:${cookie.name}`;
  }
}

