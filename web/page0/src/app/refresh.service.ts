import {Injectable} from '@angular/core';
import {Store} from 'src/app/store/store';
import {defaultRuntimeSettings} from './settings';
import {merge} from 'rxjs';
import {mergeAll} from 'rxjs/operators';
import {Runtime} from 'src/app/interface/runtime-interface';
import {FetchService} from './fetch.service';

@Injectable({
  providedIn: 'root',
})
export class RefreshService {
  private getStoredRuntimes(): Runtime[] {
    const runtimes = window.localStorage.getItem('runtimes');
    // TODO: handle type error
    if (runtimes) {
      return JSON.parse(runtimes) as Runtime[];
    }

    return [];
  }

  private getInitRuntimeSettings() {
    const storedRuntimes = this.getStoredRuntimes();
    if (storedRuntimes.length === 0) {
      return defaultRuntimeSettings;
    }

    return storedRuntimes.map(runtime => ({
      alias: runtime.alias,
      url: runtime.url,
    }));
  }

  refresh() {
    this.store.dispatch({
      type: 'runtime-refresh-start',
    });

    const settings = this.getInitRuntimeSettings();

    merge(
      settings.map(({url, alias}) =>
        this.fetchService.fetchRuntimeInfo(url, alias)
      )
    )
      .pipe(mergeAll())
      .subscribe({
        complete: () => {
          this.store.dispatch({type: 'runtime-load-complete'});
        },
        next: runtime => this.store.dispatch({type: 'runtime-load', runtime}),
      });
  }

  constructor(
    private store: Store,
    private fetchService: FetchService
  ) {}
}
