import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:test/test.dart';

void main() {
  late QuillController controller;

  setUp(() {
    controller = QuillController.basic();
  });

  tearDown(() {
    controller.dispose();
  });

  test('cutoff separates immediately adjacent edits into undo entries', () {
    controller
      ..replaceText(0, 0, 'A', const TextSelection.collapsed(offset: 1))
      ..cutoffHistory()
      ..replaceText(1, 0, 'B', const TextSelection.collapsed(offset: 2));

    expect(controller.document.toPlainText(), 'AB\n');

    controller.undo();
    expect(controller.document.toPlainText(), 'A\n');

    controller.undo();
    expect(controller.document.toPlainText(), '\n');
  });

  test('cutoffs bound a compound formatting history entry', () {
    controller
      ..replaceText(0, 0, 'A', const TextSelection.collapsed(offset: 1))
      ..cutoffHistory();
    final inserted = controller.document.toDelta();

    controller
      ..formatText(0, 1, Attribute.bold)
      ..formatText(0, 1, Attribute.italic);
    final formatted = controller.document.toDelta();

    controller
      ..cutoffHistory()
      ..replaceText(1, 0, 'B', const TextSelection.collapsed(offset: 2))
      ..undo();
    expect(controller.document.toDelta(), formatted);

    controller.undo();
    expect(controller.document.toDelta(), inserted);

    controller.undo();
    expect(controller.document.toPlainText(), '\n');
  });

  test('cutoff does not mutate content or either history stack', () {
    final initialContents = controller.document.toDelta();
    controller.cutoffHistory();
    expect(controller.document.toDelta(), initialContents);
    expect(controller.document.history.stack.undo, isEmpty);
    expect(controller.document.history.stack.redo, isEmpty);

    controller
      ..replaceText(0, 0, 'A', const TextSelection.collapsed(offset: 1))
      ..cutoffHistory()
      ..replaceText(1, 0, 'B', const TextSelection.collapsed(offset: 2))
      ..undo();

    final contents = controller.document.toDelta();
    final undo = List<Delta>.of(controller.document.history.stack.undo);
    final redo = List<Delta>.of(controller.document.history.stack.redo);

    controller.cutoffHistory();

    expect(controller.document.toDelta(), contents);
    expect(controller.document.history.stack.undo, undo);
    expect(controller.document.history.stack.redo, redo);
  });
}
