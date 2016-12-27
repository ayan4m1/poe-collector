import { Component } from '@angular/core';
import { SocketService } from "../service/socket";

@Component({
  selector: 'socket-status',
  template: '<a class="btn btn-default"><i [hidden]="display"></i></a>'
}) export class SocketStatusComponent {
  private display: Boolean;
  constructor(public socketService: SocketService) {
    this.display = (socketService.get() != null)
  }
}
