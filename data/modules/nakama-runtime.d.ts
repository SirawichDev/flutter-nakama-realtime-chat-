// Nakama Runtime Type Definitions
declare namespace nkruntime {
  export interface Context {
    env: { [key: string]: string };
    executionMode: string;
    headers: { [key: string]: string[] };
    queryParams: { [key: string]: string[] };
    userId: string;
    username: string;
    vars: { [key: string]: string };
    userSessionExp: number;
    sessionId: string;
    clientIp: string;
    clientPort: string;
    lang: string;
  }

  export interface Logger {
    debug(message: string, ...args: any[]): void;
    info(message: string, ...args: any[]): void;
    warn(message: string, ...args: any[]): void;
    error(message: string, ...args: any[]): void;
  }

  export interface Nakama {
    // Account methods
    accountGetId(userId: string): nkruntime.Account | null;
    accountUpdateId(
      userId: string,
      username?: string | null,
      displayName?: string | null,
      timezone?: string | null,
      location?: string | null,
      language?: string | null,
      avatarUrl?: string | null,
      metadata?: { [key: string]: any } | null
    ): void;

    // Storage methods
    storageRead(reads: nkruntime.StorageReadRequest[]): nkruntime.StorageObject[];
    storageWrite(writes: nkruntime.StorageWriteRequest[]): nkruntime.StorageWriteAck[];
    storageDelete(deletes: nkruntime.StorageDeleteRequest[]): void;

    // RPC and other methods
    [key: string]: any;
  }

  export interface Account {
    user: User;
    wallet: string;
    email: string;
    devices: Device[];
    customId: string;
    verifyTime: number;
    disableTime: number;
  }

  export interface User {
    userId: string;
    username: string;
    displayName: string;
    avatarUrl: string;
    langTag: string;
    location: string;
    timezone: string;
    metadata: { [key: string]: any };
    facebookId: string;
    googleId: string;
    gamecenterId: string;
    steamId: string;
    online: boolean;
    edgeCount: number;
    createTime: number;
    updateTime: number;
  }

  export interface Device {
    id: string;
  }

  export interface StorageReadRequest {
    collection: string;
    key: string;
    userId?: string;
  }

  export interface StorageWriteRequest {
    collection: string;
    key: string;
    userId?: string;
    value: { [key: string]: any };
    version?: string;
    permissionRead?: number;
    permissionWrite?: number;
  }

  export interface StorageDeleteRequest {
    collection: string;
    key: string;
    userId?: string;
    version?: string;
  }

  export interface StorageObject {
    collection: string;
    key: string;
    userId: string;
    value: { [key: string]: any };
    version: string;
    permissionRead: number;
    permissionWrite: number;
    createTime: number;
    updateTime: number;
  }

  export interface StorageWriteAck {
    collection: string;
    key: string;
    userId: string;
    version: string;
  }

  export interface Initializer {
    registerRpc(id: string, fn: Function): void;
    registerRtBefore(id: string, fn: Function): void;
    registerRtAfter(id: string, fn: Function): void;
    registerMatchmakerMatched(fn: Function): void;
    registerMatch(name: string, fn: object): void;
    registerLeaderboardReset(fn: Function): void;
    registerTournamentReset(fn: Function): void;
    registerTournamentEnd(fn: Function): void;
  }
}




