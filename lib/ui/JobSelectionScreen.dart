import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../repository/JobRepository.dart';
import '../model/Job.dart';

class JobSelectionScreen extends StatefulWidget {
  @override
  State<JobSelectionScreen> createState() => _JobSelectionScreenState();
}

class _JobSelectionScreenState extends State<JobSelectionScreen> {
  final _repo = JobRepository();
  List<Job> _jobs = [];
  Job? _selectedJob;

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    final jobs = await _repo.fetchJobs();
    setState(() => _jobs = jobs);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select a Job')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<Job>(
              value: _selectedJob,
              items:
                  _jobs.map((job) {
                    return DropdownMenuItem(value: job, child: Text(job.name));
                  }).toList(),
              onChanged: (j) => setState(() => _selectedJob = j),
              decoration: const InputDecoration(
                labelText: 'Job',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed:
                  _selectedJob == null
                      ? null
                      : () {
                        // navigate to camera picker
                        Navigator.pushNamed(
                          context,
                          '/photoQueue',
                          arguments: _selectedJob,
                        );
                      },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}


//
