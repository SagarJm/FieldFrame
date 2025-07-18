import '../model/Job.dart';

class JobRepository {
  Future<List<Job>> fetchJobs() async {
    // in real life hit your backend
    await Future.delayed(const Duration(milliseconds: 300));
    return [
      Job(id: '1', name: 'Electrical Repair'),
      Job(id: '2', name: 'Plumbing'),
    ];
  }
}
