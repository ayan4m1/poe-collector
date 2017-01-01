import { NgModule } from '@angular/core';
import { BrowserModule } from '@angular/platform-browser';
import { FormsModule } from '@angular/forms';
import { RouterModule, Routes } from '@angular/router';

import { AppComponent } from './app.component';
import { RiverComponent } from './component/river';
import { SearchComponent } from './component/search';
import { PricingComponent } from './component/pricing';
import { SearchesComponent } from './component/searches';
import { HeaderComponent, NavComponent } from './component/header';

import { SpinnerComponent } from 'angular2-spinner';
import { MomentModule } from 'angular2-moment';

const routes: Routes = [
  { path: 'search', component: SearchComponent },
  { path: 'searches', component: SearchesComponent },
  { path: 'river', component: RiverComponent },
  { path: 'pricing', component: PricingComponent }
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
    NavComponent,
    HeaderComponent,
    SearchComponent,
    SearchesComponent,
    RiverComponent,
    PricingComponent
  ],
  bootstrap: [ AppComponent ]
}) export class AppModule { }
