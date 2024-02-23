// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert' as convert;
import 'dart:ffi' as ffi show Abi;
import 'dart:io' as io;

import 'package:engine_build_configs/engine_build_configs.dart';
import 'package:engine_repo_tools/engine_repo_tools.dart';
import 'package:engine_tool/src/build_utils.dart';
import 'package:engine_tool/src/commands/command_runner.dart';
import 'package:engine_tool/src/environment.dart';
import 'package:engine_tool/src/logger.dart';
import 'package:litetest/litetest.dart';
import 'package:platform/platform.dart';
import 'package:process_fakes/process_fakes.dart';
import 'package:process_runner/process_runner.dart';

import 'fixtures.dart' as fixtures;

void main() {
  final Engine engine;
  try {
    engine = Engine.findWithin();
  } catch (e) {
    io.stderr.writeln(e);
    io.exitCode = 1;
    return;
  }

  final BuildConfig linuxTestConfig = BuildConfig.fromJson(
    path: 'ci/builders/linux_test_config.json',
    map: convert.jsonDecode(fixtures.testConfig('Linux'))
        as Map<String, Object?>,
  );

  final BuildConfig macTestConfig = BuildConfig.fromJson(
    path: 'ci/builders/mac_test_config.json',
    map: convert.jsonDecode(fixtures.testConfig('Mac-12'))
        as Map<String, Object?>,
  );

  final BuildConfig winTestConfig = BuildConfig.fromJson(
    path: 'ci/builders/win_test_config.json',
    map: convert.jsonDecode(fixtures.testConfig('Windows-11'))
        as Map<String, Object?>,
  );

  final Map<String, BuildConfig> configs = <String, BuildConfig>{
    'linux_test_config': linuxTestConfig,
    'linux_test_config2': linuxTestConfig,
    'mac_test_config': macTestConfig,
    'win_test_config': winTestConfig,
  };

  (Environment, List<List<String>>) linuxEnv(Logger logger) {
    final List<List<String>> runHistory = <List<String>>[];
    return (
      Environment(
        abi: ffi.Abi.linuxX64,
        engine: engine,
        platform: FakePlatform(operatingSystem: Platform.linux),
        processRunner: ProcessRunner(
          processManager: FakeProcessManager(onStart: (List<String> command) {
            runHistory.add(command);
            return FakeProcess();
          }, onRun: (List<String> command) {
            runHistory.add(command);
            return io.ProcessResult(81, 0, '', '');
          }),
        ),
        logger: logger,
      ),
      runHistory
    );
  }

  test('can find host runnable build', () async {
    final Logger logger = Logger.test();
    final (Environment env, _) = linuxEnv(logger);
    final List<GlobalBuild> result = runnableBuilds(env, configs);
    expect(result.length, equals(2));
    expect(result[0].name, equals('build_name'));
  });

  test('build command invokes gn', () async {
    final Logger logger = Logger.test();
    final (Environment env, List<List<String>> runHistory) = linuxEnv(logger);
    final ToolCommandRunner runner = ToolCommandRunner(
      environment: env,
      configs: configs,
    );
    final int result = await runner.run(<String>[
      'build',
      '--config',
      'build_name',
    ]);
    expect(result, equals(0));
    expect(runHistory.length, greaterThanOrEqualTo(1));
    expect(runHistory[0].length, greaterThanOrEqualTo(1));
    expect(runHistory[0][0], contains('gn'));
  });

  test('build command invokes ninja', () async {
    final Logger logger = Logger.test();
    final (Environment env, List<List<String>> runHistory) = linuxEnv(logger);
    final ToolCommandRunner runner = ToolCommandRunner(
      environment: env,
      configs: configs,
    );
    final int result = await runner.run(<String>[
      'build',
      '--config',
      'build_name',
    ]);
    expect(result, equals(0));
    expect(runHistory.length, greaterThanOrEqualTo(2));
    expect(runHistory[1].length, greaterThanOrEqualTo(1));
    expect(runHistory[1][0], contains('ninja'));
  });
}
