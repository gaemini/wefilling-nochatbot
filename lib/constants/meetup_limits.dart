const int minMeetupParticipants = 3;
const int maxMeetupParticipants = 10;

const List<int> meetupParticipantOptions = <int>[
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
];

bool isValidMeetupParticipantLimit(int value) =>
    value >= minMeetupParticipants && value <= maxMeetupParticipants;
