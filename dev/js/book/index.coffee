ko = require("knockout")
$ = require("jquery")
_ = require("underscore")
CodeMirror = require("codemirror")

# ======================================================= Register Knockout bindings

require("bindings")


# ======================================================= String Util

srcTrim = (s) ->
  lines = s.split("\n")
  indent = Infinity
  for line in lines
    lineIndent = line.search(/[^ ]/)
    indent = Math.min(indent, lineIndent) if lineIndent != -1
  if indent != Infinity
    lines = for line in lines
      line.substr(indent)
  return lines.join("\n").trim()

XRegExp = require('xregexp').XRegExp
parseUniforms = (src) ->
  regex = XRegExp('uniform +(?<type>[^ ]+) +(?<name>[^ ;]+) *;', 'g')

  uniforms = {}
  XRegExp.forEach(src, regex, (match) ->
    uniforms[match.name] = {
      type: match.type
    }
  )
  return uniforms


# ======================================================= Animation Util

rafAnimate = (callback) ->
  animate = () ->
    require("raf")(animate)
    callback()
  animate()


# ======================================================= Knockout Util

makeEqualObservables = (o1, o2) ->
  value = undefined

  ko.computed () ->
    newValue = o1()
    if value != newValue
      value = newValue
      o2(value)

  ko.computed () ->
    newValue = o2()
    if value != newValue
      value = newValue
      o1(value)




showTip = ($el, position, message) ->
  Tip = require("tip")
  tip = new Tip("<div style='width: 270px'>#{message}</div>")
  tip.suggested = () -> undefined # hack to stop it jumping around
  tip.position(position).show($el[0])


# ======================================================= Shader Model

# TODO: this will be part of the uniform itself, so we can have separate, controllable timelines
startTime = Date.now()
updateUniforms = (model) ->
  uniforms = model.uniforms()
  changed = false

  for own name, uniform of uniforms
    if name == "time" && uniform.type == "float"
      if model.playing()
        model.time(Date.now() - model.playing())
      time = model.time() / 1000
      if uniform.value != time
        uniform.value = model.time() / 1000
        changed = true
    else if name == "webcam" && uniform.type == "sampler2D"
      uniform.value = require("webcam")()
      changed = true

  if changed
    model.uniforms(uniforms)


shaderModel = (src) ->
  model = {
    bounds: ko.observable({
      minX: 0
      minY: 0
      maxX: 1
      maxY: 1
    })
    src: ko.observable(src)
    compiledSrc: ko.observable(src)
    errors: ko.observable([])
    annotations: ko.observable([])
    uniforms: ko.observable({})
    playing: ko.observable(false)
    time: ko.observable(0)
    position: ko.observable([0.3, 0.4])
  }

  rafAnimate () ->
    updateUniforms(model)

  model.play = ->
    model.playing(Date.now() - model.time())
  model.pause = ->
    model.playing(false)
  model.rewind = ->
    model.time(0)
    if model.playing()
      model.playing(Date.now() - model.time())

  model.play()

  # compile and mark errors
  ko.computed () ->
    src = model.src()
    errors = require("glsl-error")(src)
    model.errors(errors)

    if !_.some(errors)
      model.compiledSrc(src)

  # update uniforms
  ko.computed () ->
    src = model.compiledSrc()
    # TODO: make it not clear set values, we'll need to .peek() at uniforms
    model.uniforms(parseUniforms(src))

  # parse the src
  parsedSrc = ko.computed () ->
    src = model.compiledSrc()
    try
      require("parse-glsl").parse(src, "fragment_start")

  # interpret based on position and annotate the line-by-line evaluation
  (ko.computed () ->
    position = model.position()
    if position
      # round it
      round = (x) ->
        mult = Math.pow(10, 3)
        Math.round(x*mult) / mult
      position = (round(x) for x in position)

      ast = parsedSrc()
      uniforms = model.uniforms()
      env = {
        gl_FragColor: [0, 0, 0, 0]
        position: position
      }
      for own name, uniform of uniforms
        env[name] = if _.isNumber(uniform.value) then [uniform.value] else uniform.value
      try
        require("interpret")(env, ast)
        annotations = require("interpret").extractStatements(ast)
        model.annotations(annotations)
      catch e
        model.annotations([])
        console.log ast
        # throw e
  ).extend({ throttle: 1 })

  return model


# ======================================================= Graph Model

makeGraphF = (src) ->
  ast = require("parse-glsl").parse(src, "assignment_expression")
  return (x) ->
    require("interpret")({x: [x]}, ast)
    return ast.evaluated[0]

graphModel = (src, $deconstruct) ->
  model = {
    src: ko.observable(src) # what's in the editor
    compiledSrc: ko.observable(src) # last src that successfully compiled
    showSrc: ko.observable(src) # what the graph shows

    annotations: ko.observable([])
    errors: ko.observable([])
    bounds: ko.observable({
      minX: -2
      minY: -2
      maxX: 2
      maxY: 2
    })
    f: ko.observable(false)
  }

  ko.computed () ->
    src = model.src()
    compiled = false
    try
      f = makeGraphF(src)
      if _.isNumber(f(0))
        compiled = true
    if compiled
      model.compiledSrc(src)
      model.errors([])
    else
      model.errors([{line: 0, message: ""}])

  ko.computed () ->
    model.showSrc(model.compiledSrc())

  ko.computed () ->
    src = model.showSrc()
    model.f(makeGraphF(src))

  if $deconstruct
    ko.computed () ->
      src = model.compiledSrc()
      require("deconstruct")({
        div: $deconstruct
        src: src
      })

    $deconstruct.on("mouseover", ".deconstruct-node", (e) ->
      src = $(this).text()
      model.showSrc(src)
    )
    $deconstruct.on("mouseout", ".deconstruct-node", (e) ->
      model.showSrc(model.compiledSrc())
    )

  return model


# ======================================================= Exercise Model

exerciseModel = (startSrc, solutionSrcs) ->
  model = {
    workSrcs: [startSrc]
    solutionSrcs: solutionSrcs
    workSrc: ko.observable(startSrc)
    solutionSrc: ko.observable(solutionSrcs[0])

    solved: ko.observable(false)
    currentExercise: ko.observable(0)
    numExercises: solutionSrcs.length
  }

  model.onFirst = ko.computed () -> model.currentExercise() == 0
  model.onLast = ko.computed () -> model.currentExercise() == model.numExercises - 1
  model.previous = () ->
    if !model.onFirst()
      model.currentExercise(model.currentExercise() - 1)
  model.next = () ->
    if !model.onLast()
      model.currentExercise(model.currentExercise() + 1)

  ko.computed () ->
    currentExercise = model.currentExercise()
    model.solutionSrc(model.solutionSrcs[currentExercise])
    if model.workSrcs[currentExercise]
      model.workSrc(model.workSrcs[currentExercise])

  ko.computed () ->
    workSrc = model.workSrc()
    model.workSrcs[model.currentExercise.peek()] = workSrc

  return model


# ======================================================= Shader Example

buildShaderExample = ($replace) ->
  src = srcTrim($replace.text())
  model = shaderModel(src)

  $div = $("""
  <div class="book-view-edit">
    <div class="book-view" data-bind="panAndZoom: {bounds: bounds, position: position}">
      <canvas data-bind="drawShader: {bounds: bounds, src: compiledSrc, uniforms: uniforms}"></canvas>
      <canvas class="book-grid" data-bind="drawGrid: {bounds: bounds, color: 'white'}"></canvas>
      <!--<div class="book-crosshair" data-bind="relPosition: {bounds: bounds, position: position}"></div>-->
      <!--<div style="position: absolute">
        <div data-bind="click: play">Play</div>
        <div data-bind="click: pause">Pause</div>
        <div data-bind="click: rewind">Rewind</div>
      </div>-->
    </div>
    <div class="book-edit book-editor" data-bind="editorShader: {src: src, multiline: true, errors: errors, annotations: annotations}"></div>
  </div>
  """)

  $replace.replaceWith($div)
  ko.applyBindings(model, $div[0]) # for sizing, this has to be after the div has been added to the body

  return $div


buildShaderTemp = ($replace) ->
  src = srcTrim($replace.find(".code").text())
  shown = srcTrim($replace.find(".shown").text())
  model = shaderModel(src)
  model.shown = ko.observable(shown)

  $div = $("""
  <div class="book-view-edit">
    <div class="book-view" data-bind="panAndZoom: {bounds: bounds, position: position}">
      <canvas data-bind="drawShader: {bounds: bounds, src: compiledSrc, uniforms: uniforms}"></canvas>
      <canvas class="book-grid" data-bind="drawGrid: {bounds: bounds, color: 'white'}"></canvas>
    </div>
    <div class="book-edit book-editor" data-bind="editorShader: {src: shown, multiline: true, errors: errors, annotations: annotations}"></div>
  </div>
  """)

  $replace.replaceWith($div)
  ko.applyBindings(model, $div[0]) # for sizing, this has to be after the div has been added to the body

  return $div


# ======================================================= Shader Exercise

testEqualPixelArrays = (p1, p2) ->
  len = p1.length

  # sample 1000 random locations to test equivalence
  equivalent = true
  for i in [0...1000]
    location = Math.floor(Math.random()*len)
    diff = Math.abs(p1[location] - p2[location])
    if diff > 2
      equivalent = false

  return equivalent


buildShaderExercise = ($replace) ->
  $div = $("""
  <div>
    <div class="book-view-edit">
      <div class="book-view" data-bind="panAndZoom: {bounds: work.bounds, position: work.position}">
        <canvas class="shader-work" data-bind="drawShader: {bounds: work.bounds, src: work.compiledSrc, uniforms: work.uniforms}"></canvas>
        <canvas class="book-grid" data-bind="drawGrid: {bounds: work.bounds, color: 'white'}"></canvas>
      </div>
      <div class="book-edit book-editor" data-bind="editorShader: {src: work.src, multiline: true, errors: work.errors, annotations: work.annotations}">
      </div>
    </div>
    <div class="book-view-edit">
      <div class="book-view" data-bind="panAndZoom: {bounds: work.bounds, position: work.position}">
        <canvas class="shader-solution" data-bind="drawShader: {bounds: work.bounds, src: solution.compiledSrc, uniforms: work.uniforms}"></canvas>
        <canvas class="book-grid" data-bind="drawGrid: {bounds: work.bounds, color: 'white'}"></canvas>
      </div>
      <div class="book-edit" style="font-family: helvetica; font-size: 30px;" data-bind="with: exercise">
        <div style="float: left; margin-top: 2px; font-size: 26px">
          <i class="icon-arrow-left"></i>
        </div>
        <div style="margin-left: 30px;">
          <div>
            Make this
          </div>
          <div data-bind="style: {visibility: solved() ? 'visible' : 'hidden'}">
            <span style="color: #090; font-size: 42px"><i class="icon-ok"></i> <span style="font-size: 42px; font-weight: bold">Solved</span></span>
          </div>
          <div>
            <button style="vertical-align: middle" data-bind="disable: onFirst, event: {click: previous}">&#x2190;</button>
            <span data-bind="text: currentExercise()+1"></span> of <span data-bind="text: numExercises"></span>
            <button style="vertical-align: middle" data-bind="disable: onLast, event: {click: next}">&#x2192;</button>
          </div>
        </div>
      </div>
    </div>
  </div>
  """)

  startSrc = srcTrim($replace.find(".start").text())
  solutionSrcs = $replace.find(".solution").map () ->
    srcTrim($(this).text())

  model = {
    exercise: exerciseModel(startSrc, solutionSrcs)
    work: shaderModel(startSrc)
    solution: shaderModel(solutionSrcs[0])
  }

  makeEqualObservables(model.solution.src, model.exercise.solutionSrc)
  makeEqualObservables(model.work.src, model.exercise.workSrc)

  ko.computed () ->
    model.work.compiledSrc()
    model.solution.compiledSrc()
    setTimeout(checkSolved, 0)

  checkSolved = () ->
    workPixels = $div.find(".shader-work")[0].shader?.readPixels()
    solutionPixels = $div.find(".shader-solution")[0].shader?.readPixels()

    if workPixels && solutionPixels
      solved = testEqualPixelArrays(workPixels, solutionPixels)
      model.exercise.solved(solved)


  $replace.replaceWith($div)
  ko.applyBindings(model, $div[0])

  return $div


# ======================================================= Evaluator

buildEvaluator = ($replace) ->
  src = srcTrim($replace.text())
  $div = $("""
  <div class="book-text">
    <div class="book-editor" data-bind="editorShader: {src: src, multiline: false, annotations: annotations, errors: errors}"></div>
  </div>
  """)

  model = {
    src: ko.observable(src)
    annotations: ko.observable([])
    errors: ko.observable([])
  }

  ko.computed () ->
    src = model.src()
    try
      ast = require("parse-glsl").parse(src, "assignment_expression")
      # console.log ast
      require("interpret")({}, ast)

      result = require("interpret").vecToString(ast.evaluated, 3)
      # console.log result
      model.annotations([{line: 0, message: result}])
      model.errors([])
    catch e
      model.annotations([])
      model.errors([{line: 0, message: ""}])

  $replace.replaceWith($div)
  ko.applyBindings(model, $div[0])

  return $div


# ======================================================= Graph Example

buildGraphExample = ($replace) ->
  src = srcTrim($replace.text())
  $div = $("""
  <div class="split">
    <div class="left" data-bind="panAndZoom: {bounds: bounds}">
      <canvas class="book-grid" data-bind="drawGrid: {bounds: bounds, color: 'black'}"></canvas>
      <canvas data-bind="drawGraph: {bounds: bounds, f: f, color: 'rgba(0, 0, 180, 1.0)'}"></canvas>
    </div>
    <div class="right">
      <div class="book-editor" data-bind="editorShader: {src: src, multiline: false, errors: errors, annotations: annotations}"></div>
      <div class="deconstruct"></div>
    </div>
  </div>
  """)

  $deconstruct = $div.find(".deconstruct")
  model = graphModel(src, $deconstruct)

  $replace.replaceWith($div)
  ko.applyBindings(model, $div[0])

  return $div


# ======================================================= Graph Exercise

testEqualGraphs = (f1, f2) ->
  # sample 100 random locations to test equivalence
  equivalent = true
  for i in [0...100]
    x = Math.random()*100 - 50
    diff = Math.abs(f1(x) - f2(x))
    if diff > .0001
      equivalent = false

  return equivalent


buildGraphExercise = ($replace) ->
  $div = $("""
  <div class="split">
    <div class="left" data-bind="panAndZoom: {bounds: work.bounds}">
      <canvas class="book-grid" data-bind="drawGrid: {bounds: work.bounds, color: 'black'}"></canvas>
      <canvas data-bind="drawGraph: {bounds: work.bounds, f: work.f, color: 'rgba(0, 0, 180, 1.0)'}"></canvas>
      <canvas data-bind="drawGraph: {bounds: work.bounds, f: solution.f, color: 'rgba(180, 0, 0, 0.75)'}"></canvas>
    </div>
    <div class="right">
      <div style="min-height: 264px">
        <div class="book-editor" data-bind="editorShader: {src: work.src, multiline: false, errors: work.errors, annotations: work.annotations}"></div>
        <div class="deconstruct"></div>
      </div>
      <div style="font-family: helvetica; font-size: 30px; margin-bottom: 72px" data-bind="with: exercise">
        <div style="float: left; margin-top: 2px; font-size: 26px">
          <i class="icon-arrow-left"></i>
        </div>
        <div style="margin-left: 30px;">
          <div>
            Make the <span style='color: rgba(180, 0, 0, 0.75); font-weight: bold'>red</span> graph
          </div>
          <div data-bind="style: {visibility: solved() ? 'visible' : 'hidden'}">
            <span style="color: #090; font-size: 42px"><i class="icon-ok"></i> <span style="font-size: 42px; font-weight: bold">Solved</span></span>
          </div>
          <div>
            <button style="vertical-align: middle" data-bind="disable: onFirst, event: {click: previous}">&#x2190;</button>
            <span data-bind="text: currentExercise()+1"></span> of <span data-bind="text: numExercises"></span>
            <button style="vertical-align: middle" data-bind="disable: onLast, event: {click: next}">&#x2192;</button>
          </div>
        </div>
      </div>
    </div>
  </div>
  """)

  startSrc = srcTrim($replace.find(".start").text())
  solutionSrcs = $replace.find(".solution").map () ->
    srcTrim($(this).text())

  $deconstruct = $div.find(".deconstruct")

  model = {
    exercise: exerciseModel(startSrc, solutionSrcs)
    work: graphModel(startSrc, $deconstruct)
    solution: graphModel(solutionSrcs[0])
  }

  makeEqualObservables(model.solution.src, model.exercise.solutionSrc)
  makeEqualObservables(model.work.src, model.exercise.workSrc)

  ko.computed () ->
    model.work.compiledSrc()
    model.solution.f()
    solved = false
    try
      f = makeGraphF(model.work.compiledSrc())
      solved = testEqualGraphs(f, model.solution.f())
    catch e
      solved = false
    model.exercise.solved(solved)

  $replace.replaceWith($div)
  ko.applyBindings(model, $div[0])

  return $div






# ======================================================= Build Util

build = ($selection, buildFunction) ->
  $selection.each () ->
    $replace = $(this)
    $explains = $replace.find(".explain")
    $explains.remove()

    $div = buildFunction($replace)

    $explains.each () ->
      $explain = $(this)
      select = $explain.attr("select")
      position = $explain.attr("position")
      message = $explain.html()

      showTip($div.find(select), position, message)


# ======================================================= Build

do ->
  build($(".shader-example"), buildShaderExample)
  build($(".shader-exercise"), buildShaderExercise)
  build($(".evaluator"), buildEvaluator)
  build($(".graph-example"), buildGraphExample)
  build($(".graph-exercise"), buildGraphExercise)
  build($(".shader-temp"), buildShaderTemp)

  $("code").each () ->
    CodeMirror.runMode($(this).text(), "text/x-glsl", this)
    $(this).addClass("cm-s-default")
