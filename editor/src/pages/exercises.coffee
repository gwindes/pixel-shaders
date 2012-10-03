editor = require("../editor")


exercises = [{
workspace: """
precision mediump float;

varying vec2 position;

void main() {
  gl_FragColor.r = 1.0;
  gl_FragColor.g = 0.0;
  gl_FragColor.b = 0.0;
  gl_FragColor.a = 1.0;
}
"""
solution: """
precision mediump float;

varying vec2 position;

void main() {
  gl_FragColor.r = 0.0;
  gl_FragColor.g = 0.0;
  gl_FragColor.b = 1.0;
  gl_FragColor.a = 1.0;
}
"""
},{
solution: """
precision mediump float;

varying vec2 position;

void main() {
  gl_FragColor.r = 1.0;
  gl_FragColor.g = 1.0;
  gl_FragColor.b = 0.0;
  gl_FragColor.a = 1.0;
}
"""
},{
solution: """
precision mediump float;

varying vec2 position;

void main() {
  gl_FragColor.r = 1.0;
  gl_FragColor.g = 0.5;
  gl_FragColor.b = 0.0;
  gl_FragColor.a = 1.0;
}
"""
},{
solution: """
precision mediump float;

varying vec2 position;

void main() {
  gl_FragColor.r = 0.5;
  gl_FragColor.g = 0.5;
  gl_FragColor.b = 0.5;
  gl_FragColor.a = 1.0;
}
"""
}]




testEqualEditors = (e1, e2) ->
  e1.snapshot(300,300) == e2.snapshot(300,300)





module.exports = () ->
  
  editorWorkspace = editor({
    src: exercises[0].workspace
    code: $("#code")
    output: $("#output")
  })
  
  editorSolution = editor({
    src: exercises[0].solution
    code: $("#makeCode")
    output: $("#makeOutput")
  })
  
  
  exercise = {
    workspace: ko.observable("")
    solution: ko.observable("")
    currentExercise: ko.observable(0)
    exercises: exercises
    solved: ko.observable(false)
    previous: () ->
      exercise.currentExercise(exercise.currentExercise() - 1)
    next: () ->
      exercise.currentExercise(exercise.currentExercise() + 1)
  }
  
  editorWorkspace.onchange (src) -> exercise.workspace(src)
  editorSolution.onchange (src) -> exercise.solution(src)
  
  ko.computed () ->
    e = exercises[exercise.currentExercise()]
    if e.workspace
      editorWorkspace.set(e.workspace)
    editorSolution.set(e.solution)
  
  ko.computed () ->
    exercise.workspace()
    exercise.solution()
    exercise.solved(testEqualEditors(editorWorkspace, editorSolution))
  
  ko.computed () ->
    exercises[exercise.currentExercise()].workspace = exercise.workspace()
  
  ko.applyBindings(exercise)
  
  