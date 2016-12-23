import { NgModule } from '@angular/core';
import { BrowserModule } from '@angular/platform-browser';
import { FormsModule } from '@angular/forms';
import { RouterModule, Routes } from '@angular/router';

import { AppComponent } from './app.component';
import { SearchComponent } from './search.component';
import { RiverComponent } from './river.component';
import { AppSettings } from './constants';

import { MomentModule } from 'angular2-moment';

const routes: Routes = [
  { path: 'search', component: SearchComponent },
  { path: 'river', component: RiverComponent }
];

@NgModule({
  imports: [
    BrowserModule,
    FormsModule,
    RouterModule.forRoot(routes),
    MomentModule
  ],
  declarations: [
    AppComponent,
    SearchComponent,
    RiverComponent
  ],
  bootstrap: [ AppComponent ]
}) export class AppModule { }
