import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../model/relic.dart';
import '../model/relic_update.dart';
import '../model/search_query.dart';
import 'relic_repository.dart';
import 'seed_generator.dart';

const _selectColumns = '''
  id, name, culture, era, material, rarity, description,
  discovered_year, discovery_site
''';

/// A SQLite-backed relic repository.
final class SqliteRelicRepository implements RelicRepository {
  SqliteRelicRepository._(this._db, this._delay, this._onQuery) {
    _initialize();
  }

  /// Opens a file-backed database, creating the parent directory if needed.
  factory SqliteRelicRepository.open({
    required String path,
    Duration delay = Duration.zero,
    void Function()? onQuery,
  }) {
    if (path != ':memory:') {
      File(path).parent.createSync(recursive: true);
    }
    final db = path == ':memory:' ? sqlite3.openInMemory() : sqlite3.open(path);
    final repository = SqliteRelicRepository._(db, delay, onQuery);
    if (path != ':memory:') {
      repository.enableWal();
    }
    return repository;
  }

  /// Opens an in-memory database, primarily for tests.
  factory SqliteRelicRepository.inMemory({
    Duration delay = Duration.zero,
    void Function()? onQuery,
  }) {
    return SqliteRelicRepository._(sqlite3.openInMemory(), delay, onQuery);
  }

  final Database _db;
  final Duration _delay;
  final void Function()? _onQuery;

  void _initialize() {
    _db.execute('PRAGMA busy_timeout = 5000;');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS relics (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        culture TEXT NOT NULL,
        era TEXT NOT NULL,
        material TEXT NOT NULL,
        rarity INTEGER NOT NULL,
        description TEXT NOT NULL,
        discovered_year INTEGER NOT NULL,
        discovery_site TEXT NOT NULL
      );
    ''');
    _db.execute(
      'CREATE INDEX IF NOT EXISTS relics_culture_idx ON relics (culture);',
    );
    _db.execute('CREATE INDEX IF NOT EXISTS relics_era_idx ON relics (era);');
  }

  /// Enables WAL for file-backed databases.
  void enableWal() {
    _db.execute('PRAGMA journal_mode = WAL;');
    _db.execute('PRAGMA synchronous = NORMAL;');
  }

  @override
  Future<Relic?> findById(int id) {
    return _query(() => _findByIdSync(id));
  }

  @override
  Future<List<Relic>> findByIds(Set<int> ids) {
    if (ids.isEmpty) {
      return Future.value(const []);
    }
    final placeholders = List.filled(ids.length, '?').join(',');
    return _query(() {
      final rows = _db.select(
        'SELECT $_selectColumns FROM relics WHERE id IN ($placeholders);',
        ids.toList(),
      );
      return [for (final row in rows) _fromRow(row)];
    });
  }

  @override
  Future<List<Relic>> search(SearchQuery query) {
    final where = <String>[];
    final parameters = <Object?>[];

    if (query.text.isNotEmpty) {
      where.add('(name LIKE ? OR description LIKE ?)');
      final pattern = '%${query.text}%';
      parameters
        ..add(pattern)
        ..add(pattern);
    }
    if (query.culture != null) {
      where.add('LOWER(culture) = ?');
      parameters.add(query.culture);
    }
    if (query.era != null) {
      where.add('LOWER(era) = ?');
      parameters.add(query.era);
    }

    final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    parameters.add(query.limit);
    return _query(() {
      final rows = _db.select(
        'SELECT $_selectColumns FROM relics $clause '
        'ORDER BY rarity DESC, id ASC LIMIT ?;',
        parameters,
      );
      return [for (final row in rows) _fromRow(row)];
    });
  }

  @override
  Future<Relic?> update(int id, RelicUpdate update) {
    if (update.isEmpty) {
      return findById(id);
    }

    final assignments = <String>[];
    final parameters = <Object?>[];
    void set(String column, Object? value) {
      if (value != null) {
        assignments.add('$column = ?');
        parameters.add(value);
      }
    }

    set('name', update.name);
    set('culture', update.culture);
    set('era', update.era);
    set('material', update.material);
    set('rarity', update.rarity);
    set('description', update.description);
    set('discovered_year', update.discoveredYear);
    set('discovery_site', update.discoverySite);
    parameters.add(id);

    return _query(() {
      _db.execute(
        'UPDATE relics SET ${assignments.join(', ')} WHERE id = ?;',
        parameters,
      );
      if (_db.updatedRows == 0) {
        return null;
      }
      return _findByIdSync(id);
    });
  }

  @override
  Future<int> rowCount() {
    return _query(_rowCountSync);
  }

  /// Seeds [count] relics. Does nothing when the table already has rows,
  /// unless [reset] is true.
  Future<void> seed(int count, {bool reset = false}) async {
    if (reset) {
      _db.execute('DROP TABLE IF EXISTS relics;');
      _initialize();
    } else if (_rowCountSync() > 0) {
      return;
    }

    final generator = RelicSeedGenerator();
    final statement = _db.prepare('''
      INSERT INTO relics (
        id, name, culture, era, material, rarity, description,
        discovered_year, discovery_site
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
    ''');

    _db.execute('BEGIN IMMEDIATE;');
    try {
      for (var id = 1; id <= count; id++) {
        final relic = generator.generate(id);
        statement.execute([
          relic.id,
          relic.name,
          relic.culture,
          relic.era,
          relic.material,
          relic.rarity,
          relic.description,
          relic.discoveredYear,
          relic.discoverySite,
        ]);
      }
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    } finally {
      statement.close();
    }
  }

  @override
  void close() {
    _db.close();
  }

  Future<T> _query<T>(T Function() action) async {
    _onQuery?.call();
    if (_delay > Duration.zero) {
      await Future<void>.delayed(_delay);
    }
    return action();
  }

  Relic? _findByIdSync(int id) {
    final rows = _db.select(
      'SELECT $_selectColumns FROM relics WHERE id = ? LIMIT 1;',
      [id],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  int _rowCountSync() {
    final row = _db.select('SELECT COUNT(*) AS count FROM relics;').first;
    return row['count'] as int;
  }

  Relic _fromRow(Row row) {
    return Relic(
      id: row['id'] as int,
      name: row['name'] as String,
      culture: row['culture'] as String,
      era: row['era'] as String,
      material: row['material'] as String,
      rarity: row['rarity'] as int,
      description: row['description'] as String,
      discoveredYear: row['discovered_year'] as int,
      discoverySite: row['discovery_site'] as String,
    );
  }
}
