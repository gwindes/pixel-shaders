// Generated by CoffeeScript 1.4.0
(function() {
  var $, Emitter, codemirror;

  $ = require("jquery");

  codemirror = require("codemirror");

  Emitter = require('emitter');

  module.exports = function(opts) {
    var $annotations, $div, annotations, cm, cmOpts, editor, errors, multiline, src, update, widgets;
    $div = $(opts.div);
    multiline = opts.multiline || false;
    src = opts.src || "";
    errors = opts.errors || {};
    annotations = opts.annotations || {};
    widgets = opts.widgets || {};
    cmOpts = {
      mode: "text/x-glsl",
      value: src,
      lineNumbers: true,
      matchBrackets: true
    };
    if (!multiline) {
      cmOpts.lineNumberFormatter = function(n) {
        return "";
      };
    }
    cm = codemirror($div[0], cmOpts);
    if (multiline) {
      cm.setSize("100%", $div.innerHeight());
    } else {
      cm.setSize("100%", cm.defaultTextHeight() + 8);
    }
    $annotations = $("<div class='editor-annotations'></div>");
    $(cm.getScrollerElement()).find(".CodeMirror-lines").append($annotations);
    editor = {
      codemirror: cm,
      src: function() {
        return src;
      }
    };
    Emitter(editor);
    update = function() {
      var $annotation, annotation, charPos, error, line, xyPos, _i, _j, _k, _len, _len1, _ref, _results;
      for (line = _i = 0, _ref = cm.lineCount(); 0 <= _ref ? _i < _ref : _i > _ref; line = 0 <= _ref ? ++_i : --_i) {
        cm.removeLineClass(line, "wrap", "editor-error");
      }
      for (_j = 0, _len = errors.length; _j < _len; _j++) {
        error = errors[_j];
        cm.addLineClass(error.line, "wrap", "editor-error");
      }
      $annotations.html("");
      _results = [];
      for (_k = 0, _len1 = annotations.length; _k < _len1; _k++) {
        annotation = annotations[_k];
        if (cm.getLine(annotation.line) !== void 0) {
          charPos = {
            line: annotation.line,
            ch: cm.getLine(annotation.line).length
          };
          xyPos = cm.cursorCoords(charPos, "local");
          $annotation = $("<div class='editor-annotation'></div>");
          codemirror.runMode(annotation.message, "text/x-glsl", $annotation[0]);
          $annotation.css({
            left: xyPos.left,
            top: xyPos.top
          });
          _results.push($annotations.append($annotation));
        } else {
          _results.push(void 0);
        }
      }
      return _results;
    };
    editor.set = function(o) {
      errors = o.errors || errors;
      annotations = o.annotations || annotations;
      widgets = o.widgets || widgets;
      return update();
    };
    cm.on("change", function() {
      src = cm.getValue();
      update();
      return editor.emit("change", src);
    });
    return editor;
  };

}).call(this);