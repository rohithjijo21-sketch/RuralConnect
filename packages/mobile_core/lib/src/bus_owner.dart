import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'api.dart';
import 'journey_map.dart';
import 'package:latlong2/latlong.dart';

String busDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class BusOwnerScreen extends StatefulWidget {
  final Api api;
  const BusOwnerScreen({super.key, required this.api});
  @override
  State<BusOwnerScreen> createState() => _BusOwnerState();
}

class _BusOwnerState extends State<BusOwnerScreen> {
  Map<String, dynamic>? data;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    run(load);
  }

  Future<void> load() async {
    final d = await widget.api.request('/bus-owner/workspace');
    if (mounted) setState(() => data = Map<String, dynamic>.from(d));
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open(Widget form) async {
    if (await Navigator.of(
          context,
        ).push<bool>(MaterialPageRoute(builder: (_) => form)) ==
        true) {
      await run(load);
    }
  }

  List list(String key) => data?[key] as List? ?? [];
  @override
  Widget build(BuildContext context) {
    final owner = data?['owner'] as Map?;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Your bus business'),
          actions: [
            IconButton(
              onPressed: busy ? null : () => run(load),
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh workspace',
            ),
          ],
          bottom: owner == null
              ? null
              : const TabBar(
                  tabs: [
                    Tab(text: 'Buses'),
                    Tab(text: 'Routes'),
                    Tab(text: 'Timetables'),
                  ],
                ),
        ),
        body: Column(
          children: [
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (owner != null)
              ListTile(
                leading: Icon(
                  owner['status'] == 'APPROVED'
                      ? Icons.verified
                      : Icons.pending_actions,
                ),
                title: Text(owner['name'].toString()),
                subtitle: Text(
                  owner['status'] == 'APPROVED'
                      ? 'Owner approved. Each bus also needs approval.'
                      : 'Owner review pending. You can save buses, routes and timetables. Services stay private until approved.',
                ),
              ),
            Expanded(
              child: data == null
                  ? const Center(child: Text('Loading workspace…'))
                  : owner == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.directions_bus, size: 64),
                            const SizedBox(height: 16),
                            const Text(
                              'Set up your bus business',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Add your buses, route stops and one-off or recurring timetables. Owner and vehicle review is required before services appear to passengers.',
                            ),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: busy
                                  ? null
                                  : () => open(
                                      BusSetupForm(
                                        api: widget.api,
                                        kind: 'owner',
                                        workspace: data!,
                                      ),
                                    ),
                              child: const Text('Create owner workspace'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : TabBarView(
                      children: [
                        section(
                          'Your buses',
                          'Add bus',
                          () => open(
                            BusSetupForm(
                              api: widget.api,
                              kind: 'vehicle',
                              workspace: data!,
                            ),
                          ),
                          list('vehicles')
                              .map(
                                (v) => Card(
                                  child: ListTile(
                                    leading: const Icon(Icons.directions_bus),
                                    title: Text(v['registration']),
                                    subtitle: Text(
                                      '${v['capacity']} seats · ${v['approved'] == true ? 'Approved' : 'Vehicle review pending'}',
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          'Add your first bus with its registration and seating capacity.',
                        ),
                        section(
                          'Routes and stops',
                          'Add route',
                          () => open(
                            BusSetupForm(
                              api: widget.api,
                              kind: 'route',
                              workspace: data!,
                            ),
                          ),
                          list('routes')
                              .map(
                                (r) => Card(
                                  child: ExpansionTile(
                                    title: Text(r['name']),
                                    subtitle: Text(
                                      '${(r['stops'] as List? ?? []).length} stops · versioned route',
                                    ),
                                    children: (r['stops'] as List? ?? [])
                                        .map<Widget>(
                                          (s) => ListTile(
                                            title: Text(s['name']),
                                            subtitle: Text(
                                              '+${s['offsetMinutes']} min · ${s['lat']}, ${s['lng']}',
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              )
                              .toList(),
                          'Add at least two ordered stops and their scheduled offsets.',
                        ),
                        section(
                          'Trips and recurring services',
                          'Add timetable',
                          () => open(
                            BusSetupForm(
                              api: widget.api,
                              kind: 'plan',
                              workspace: data!,
                            ),
                          ),
                          list('plans')
                              .map(
                                (p) => Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p['name'],
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleLarge,
                                        ),
                                        Text(
                                          '${p['departure_time']} · ${p['start_date'].toString().split('T').first} to ${p['end_date'].toString().split('T').first}',
                                        ),
                                        Text(
                                          'Weekdays (Mon=1): ${p['weekdays']}',
                                        ),
                                        Text(
                                          'Holiday exceptions: ${p['excluded_dates']}',
                                        ),
                                        Text(
                                          '${p['published_trips']} dated trips published',
                                        ),
                                        const SizedBox(height: 8),
                                        OutlinedButton.icon(
                                          onPressed: busy
                                              ? null
                                              : () => open(
                                                  BusSetupForm(
                                                    api: widget.api,
                                                    kind: 'plan',
                                                    workspace: data!,
                                                    previousPlan:
                                                        Map<
                                                          String,
                                                          dynamic
                                                        >.from(p),
                                                  ),
                                                ),
                                          icon: const Icon(Icons.edit_calendar),
                                          label: const Text(
                                            'Create revised timetable',
                                          ),
                                        ),
                                        FilledButton.icon(
                                          onPressed:
                                              busy ||
                                                  owner['status'] != 'APPROVED'
                                              ? null
                                              : () => publish(p),
                                          icon: const Icon(Icons.publish),
                                          label: const Text(
                                            'Publish dated trips',
                                          ),
                                        ),
                                        if (owner['status'] != 'APPROVED')
                                          const Text(
                                            'Awaiting owner review. Bus approval is also required.',
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          'Save a single trip or recurring timetable. Publishing creates dated services for assigned crew.',
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget section(
    String title,
    String action,
    VoidCallback onTap,
    List<Widget> items,
    String empty,
  ) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: busy ? null : onTap,
        icon: const Icon(Icons.add),
        label: Text(action),
      ),
      const SizedBox(height: 12),
      if (items.isEmpty)
        Padding(padding: const EdgeInsets.all(16), child: Text(empty)),
      ...items,
    ],
  );
  Future<void> publish(Map p) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 366)),
      helpText: 'Publish up to 31 days',
    );
    if (range == null) return;
    await run(() async {
      final r = await widget.api.request(
        '/bus-owner/plans/${p['id']}/publish',
        method: 'POST',
        data: {'fromDate': busDate(range.start), 'toDate': busDate(range.end)},
      );
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${(r['trips'] as List).length} dated services confirmed. Return to assigned services.',
            ),
          ),
        );
      }
    });
  }
}

class BusSetupForm extends StatefulWidget {
  final Api api;
  final String kind;
  final Map<String, dynamic> workspace;
  final Map<String, dynamic>? previousPlan;
  const BusSetupForm({
    super.key,
    required this.api,
    required this.kind,
    required this.workspace,
    this.previousPlan,
  });
  @override
  State<BusSetupForm> createState() => _BusSetupFormState();
}

class _BusSetupFormState extends State<BusSetupForm> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      capacity = TextEditingController(),
      exceptions = TextEditingController();
  final stops = <List<TextEditingController>>[];
  bool busy = false, recurring = false;
  String? error, vehicle, route, crew;
  DateTime start = DateTime.now(), end = DateTime.now();
  TimeOfDay time = TimeOfDay.now();
  final weekdays = <int>{1, 2, 3, 4, 5, 6, 7};
  @override
  void initState() {
    super.initState();
    addStop();
    addStop();
    final members = widget.workspace['crew'] as List? ?? [];
    if (members.isNotEmpty) crew = members.first['id'];
    final p = widget.previousPlan;
    if (p != null) {
      name.text = p['name'].toString();
      vehicle = p['vehicle_id'];
      route = p['route_version_id'];
      crew = members.any((m) => m['id'] == p['crew_id']) ? p['crew_id'] : null;
      start = DateTime.parse(p['start_date'].toString().split('T').first);
      end = DateTime.parse(p['end_date'].toString().split('T').first);
      recurring = start != end;
      final parts = p['departure_time'].toString().split(':');
      time = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      weekdays
        ..clear()
        ..addAll((p['weekdays'] as List).cast<int>());
      exceptions.text = (p['excluded_dates'] as List)
          .map((d) => d.toString().split('T').first)
          .join(', ');
    }
  }

  void addStop() => stops.add(List.generate(4, (_) => TextEditingController()));
  @override
  void dispose() {
    for (final c in [name, capacity, exceptions, ...stops.expand((s) => s)]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget text(
    TextEditingController c,
    String label, {
    TextInputType? keyboard,
    String? Function(String)? validate,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextFormField(
      controller: c,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (v) =>
          v == null || v.trim().isEmpty ? 'Required' : validate?.call(v.trim()),
    ),
  );
  Widget dropdown(
    String label,
    List choices,
    String? value,
    void Function(String?) change,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: choices
          .map<DropdownMenuItem<String>>(
            (c) => DropdownMenuItem(
              value: c['id'],
              child: Text(
                (c['name']?.toString().isNotEmpty == true
                            ? c['name']
                            : c['registration'])
                        ?.toString() ??
                    'Your crew account',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: busy ? null : change,
      validator: (v) => v == null ? 'Choose an option' : null,
    ),
  );
  Future<void> pickStop(int i) async {
    final p = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => MapLocationPicker(
          initial: mapPoint(stops[i][1].text, stops[i][2].text),
        ),
      ),
    );
    if (p == null || !mounted) return;
    setState(() {
      stops[i][1].text = p.latitude.toStringAsFixed(6);
      stops[i][2].text = p.longitude.toStringAsFixed(6);
    });
  }

  Future<void> gps(int i) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Enable location services');
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied ||
          p == LocationPermission.deniedForever) {
        throw StateError('Location permission is required');
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        stops[i][1].text = pos.latitude.toStringAsFixed(6);
        stops[i][2].text = pos.longitude.toStringAsFixed(6);
      });
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate() || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      String path;
      Map<String, dynamic> body;
      switch (widget.kind) {
        case 'owner':
          path = '/bus-owner/apply';
          body = {'name': name.text.trim()};
          break;
        case 'vehicle':
          path = '/bus-owner/vehicles';
          body = {
            'registration': name.text.trim(),
            'capacity': int.parse(capacity.text),
          };
          break;
        case 'route':
          if (stops.any((s) => mapPoint(s[1].text, s[2].text) == null)) {
            throw StateError('Choose a map location for every stop.');
          }
          path = '/operator/routes';
          body = {
            'operatorId': widget.workspace['owner']['operator_id'],
            'name': name.text.trim(),
            'stops': stops
                .map(
                  (s) => {
                    'name': s[0].text.trim(),
                    'lat': double.parse(s[1].text),
                    'lng': double.parse(s[2].text),
                    'offsetMinutes': int.parse(s[3].text),
                  },
                )
                .toList(),
          };
          break;
        default:
          if (recurring && weekdays.isEmpty) {
            throw StateError('Choose at least one operating day');
          }
          if (recurring &&
              end.isBefore(DateTime(start.year, start.month, start.day))) {
            throw StateError('End date precedes start date');
          }
          final excluded = exceptions.text
              .split(',')
              .map((v) => v.trim())
              .where((v) => v.isNotEmpty)
              .toList();
          for (final d in excluded) {
            if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d) ||
                DateTime.tryParse(d) == null) {
              throw StateError('Use YYYY-MM-DD for holiday dates');
            }
          }
          path = '/bus-owner/plans';
          body = {
            'name': name.text.trim(),
            'vehicleId': vehicle,
            'routeVersionId': route,
            'crewId': crew,
            'departureTime':
                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
            'startDate': busDate(start),
            'endDate': busDate(recurring ? end : start),
            'weekdays': recurring ? weekdays.toList() : [start.weekday],
            'excludedDates': excluded,
            if (widget.previousPlan != null)
              'previousPlanId': widget.previousPlan!['id'],
          };
      }
      await widget.api.request(path, method: 'POST', data: body);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = {
      'owner': 'Owner registration',
      'vehicle': 'Add your bus',
      'route': 'Add route and stops',
      'plan': 'Add trip / timetable',
    }[widget.kind]!;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (busy) const LinearProgressIndicator(),
              if (widget.previousPlan != null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Save creates a new timetable and keeps the original timetable and published trips unchanged. Cancel conflicting dated services before publishing the revision. Approval and scheduling checks still apply.',
                  ),
                ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              text(
                name,
                widget.kind == 'owner'
                    ? 'Bus business / owner name'
                    : widget.kind == 'vehicle'
                    ? 'Bus registration number'
                    : widget.kind == 'route'
                    ? 'Route name'
                    : 'Service name',
              ),
              if (widget.kind == 'owner')
                const Text(
                  'Saving creates an owner application. Review is required before publishing passenger-visible services.',
                ),
              if (widget.kind == 'vehicle') ...[
                text(
                  capacity,
                  'Seating capacity',
                  keyboard: TextInputType.number,
                  validate: (v) {
                    final n = int.tryParse(v);
                    return n == null || n < 1 || n > 100
                        ? 'Enter 1 to 100 seats'
                        : null;
                  },
                ),
                const Text(
                  'Bus approval is separate. Enter the registration as shown on the vehicle documents.',
                ),
              ],
              if (widget.kind == 'route') ...[
                const Text(
                  'Enter ordered stops. Coordinates must be real stop locations. First offset is 0; later offsets must increase.',
                ),
                for (var i = 0; i < stops.length; i++)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text('Stop ${i + 1}')),
                              if (stops.length > 2)
                                IconButton(
                                  onPressed: busy
                                      ? null
                                      : () {
                                          setState(() {
                                            for (final c in stops.removeAt(i)) {
                                              c.dispose();
                                            }
                                          });
                                        },
                                  icon: const Icon(Icons.remove_circle_outline),
                                  tooltip: 'Remove stop',
                                ),
                            ],
                          ),
                          text(stops[i][0], 'Stop name'),
                          OutlinedButton.icon(
                            onPressed: busy ? null : () => pickStop(i),
                            icon: const Icon(Icons.map_outlined),
                            label: Text(
                              stops[i][1].text.isEmpty
                                  ? 'Choose location on map'
                                  : 'Location chosen · Change',
                            ),
                          ),
                          ExpansionTile(
                            title: const Text('Enter coordinates manually'),
                            initiallyExpanded: false,
                            maintainState: true,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: text(
                                      stops[i][1],
                                      'Latitude',
                                      keyboard:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                            signed: true,
                                          ),
                                      validate: (v) {
                                        final n = double.tryParse(v);
                                        return n == null ||
                                                !n.isFinite ||
                                                n < -90 ||
                                                n > 90
                                            ? 'Invalid latitude'
                                            : null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: text(
                                      stops[i][2],
                                      'Longitude',
                                      keyboard:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                            signed: true,
                                          ),
                                      validate: (v) {
                                        final n = double.tryParse(v);
                                        return n == null ||
                                                !n.isFinite ||
                                                n < -180 ||
                                                n > 180
                                            ? 'Invalid longitude'
                                            : null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          OutlinedButton.icon(
                            onPressed: busy ? null : () => gps(i),
                            icon: const Icon(Icons.my_location),
                            label: const Text('Use my location at this stop'),
                          ),
                          text(
                            stops[i][3],
                            'Minutes after departure',
                            keyboard: TextInputType.number,
                            validate: (v) {
                              final n = int.tryParse(v);
                              return n == null || n < 0 || n > 1440
                                  ? 'Enter 0 to 1440 minutes'
                                  : null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => setState(addStop),
                  icon: const Icon(Icons.add),
                  label: const Text('Add another stop'),
                ),
              ],
              if (widget.kind == 'plan') ...[
                dropdown(
                  'Bus',
                  widget.workspace['vehicles'] as List,
                  vehicle,
                  (v) => setState(() => vehicle = v),
                ),
                dropdown(
                  'Route',
                  widget.workspace['routes'] as List,
                  route,
                  (v) => setState(() => route = v),
                ),
                dropdown(
                  'Assigned driver / crew',
                  widget.workspace['crew'] as List,
                  crew,
                  (v) => setState(() => crew = v),
                ),
                if ((widget.workspace['vehicles'] as List).isEmpty ||
                    (widget.workspace['routes'] as List).isEmpty)
                  const Text('Add a bus and route first, then return here.'),
                SwitchListTile(
                  title: const Text('Recurring timetable'),
                  subtitle: const Text('Off creates a single dated trip'),
                  value: recurring,
                  onChanged: busy ? null : (v) => setState(() => recurring = v),
                ),
                ListTile(
                  title: Text('Start date: ${busDate(start)}'),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: busy
                      ? null
                      : () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: start,
                            firstDate:
                                start.isBefore(
                                  DateTime.now().subtract(
                                    const Duration(days: 1),
                                  ),
                                )
                                ? start
                                : DateTime.now().subtract(
                                    const Duration(days: 1),
                                  ),
                            lastDate:
                                start.isAfter(
                                  DateTime.now().add(const Duration(days: 730)),
                                )
                                ? start.add(const Duration(days: 730))
                                : DateTime.now().add(const Duration(days: 730)),
                          );
                          if (d != null) {
                            setState(() {
                              start = d;
                              if (end.isBefore(d)) end = d;
                            });
                          }
                        },
                ),
                ListTile(
                  title: Text('Departure: ${time.format(context)}'),
                  trailing: const Icon(Icons.schedule),
                  onTap: busy
                      ? null
                      : () async {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: time,
                          );
                          if (t != null) setState(() => time = t);
                        },
                ),
                if (recurring) ...[
                  ListTile(
                    title: Text('End date: ${busDate(end)}'),
                    trailing: const Icon(Icons.calendar_month),
                    onTap: busy
                        ? null
                        : () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: end.isBefore(start) ? start : end,
                              firstDate: start,
                              lastDate: start.add(const Duration(days: 730)),
                            );
                            if (d != null) setState(() => end = d);
                          },
                  ),
                  Wrap(
                    spacing: 6,
                    children: List.generate(
                      7,
                      (i) => FilterChip(
                        label: Text(
                          ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i],
                        ),
                        selected: weekdays.contains(i + 1),
                        onSelected: busy
                            ? null
                            : (v) => setState(() {
                                if (v) {
                                  weekdays.add(i + 1);
                                } else {
                                  weekdays.remove(i + 1);
                                }
                              }),
                      ),
                    ),
                  ),
                  TextFormField(
                    controller: exceptions,
                    decoration: const InputDecoration(
                      labelText: 'Holiday dates (YYYY-MM-DD, comma separated)',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'Saved timetables stay private until owner and bus approval. Publish dates from the workspace after approval. Times use Kerala / India time.',
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy ? null : save,
                child: Text(busy ? 'Saving…' : 'Save details'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
