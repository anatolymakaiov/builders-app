import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/chat_service.dart';

void main() {
  test('counterparty leads vacancy chat title', () {
    expect(
        ChatService.chatDisplayName(
          chatData: {'jobId': 'job-a', 'jobTitle': 'Dryliner Manchester'},
          participantData: {'name': 'John Smith'},
          jobData: null,
          currentUserIsWorker: false,
          isInternalTeamChat: false,
          showTeamAvatar: false,
        ),
        'John Smith_Dryliner Manchester');
    expect(
        ChatService.chatDisplayName(
          chatData: {'jobId': 'job-a', 'jobTitle': 'Dryliner Manchester'},
          participantData: {'companyName': 'ABC Drylining Ltd'},
          jobData: null,
          currentUserIsWorker: true,
          isInternalTeamChat: false,
          showTeamAvatar: false,
        ),
        'ABC Drylining Ltd_Dryliner Manchester');
  });

  test('direct chat without vacancy has no generic Job suffix', () {
    expect(
        ChatService.directChatDisplayName(
          chatData: {},
          participantData: {
            'name': 'John Smith',
            'email': 'private@example.com',
          },
          jobData: null,
        ),
        'John Smith');
    expect(
        ChatService.directChatDisplayName(
          chatData: {'jobTitle': 'General'},
          participantData: {'name': 'private@example.com'},
          jobData: null,
        ),
        'User');
  });

  test('placeholder projection does not hide real legacy chat or job name', () {
    expect(
      ChatService.chatDisplayName(
        chatData: {'jobId': 'job-a', 'jobTitle': 'Dryliner Manchester'},
        participantData: {'companyName': 'Company'},
        jobData: {'companyName': 'ABC Drylining Ltd'},
        currentUserIsWorker: true,
        isInternalTeamChat: false,
        showTeamAvatar: false,
      ),
      'ABC Drylining Ltd_Dryliner Manchester',
    );
    expect(
      ChatService.chatDisplayName(
        chatData: {'workerName': 'John S.'},
        participantData: {'name': 'Worker'},
        jobData: null,
        currentUserIsWorker: false,
        isInternalTeamChat: false,
        showTeamAvatar: false,
      ),
      'John S.',
    );
  });
}
