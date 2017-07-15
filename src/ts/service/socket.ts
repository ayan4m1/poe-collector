import {Injectable, Inject} from '@angular/core';
import {QueryHashService} from './query-hash';

@Injectable()
export class SocketService {
  private socket: WebSocket;
  private queries: Array<String>;
  constructor(public hasher: QueryHashService) { }

  get() {

  }

  register(query: String): String {
    const queryHash = this.hasher.hash(query);

    // todo: this
    this.queries.push(queryHash);

    return queryHash;
  }

  deregister(queryId: String) {
    if (this.queries.length > 0) {
      console.log('queries');
    }
  }
}
