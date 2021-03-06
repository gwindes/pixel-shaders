evalInContext = do ->
  abs = Math.abs
  mod = (x, y) -> x - y * Math.floor(x/y)
  floor = Math.floor
  ceil = Math.ceil
  sin = Math.sin
  cos = Math.cos
  tan = Math.tan
  min = Math.min
  max = Math.max
  clamp = (x, minVal, maxVal) -> min(max(x, minVal), maxVal)
  exp = Math.exp
  pow = Math.pow
  sqrt = Math.sqrt
  fract = (x) -> x - floor(x)
  
  return (s) -> eval(s)



hasIntegers = (s) ->
  # for simulating errors on non-floating point numbers
  ret = false
  XRegExp.forEach(s, /([0-9]*\.[0-9]*)|[0-9]+/, (match) ->
    number = match[0]
    if number.indexOf(".") == -1
      ret = true
  )
  return ret

errorValue = {err: true}


hasX = (tree) ->
  if _.isArray(tree)
    return _.any(tree, hasX)
  else
    return tree == "x"




evaluate = {
  direct: (s) ->
    outputValue = errorValue
    if !hasIntegers(s)
      try
        outputValue = evalInContext(s)
      catch e
    
    return outputValue
  
  functionOfX: (s) ->
    if hasIntegers(s)
      return errorValue
    evalInContext("(function (x) {return #{s};})")
  
  hasIntegers: hasIntegers
  
  stepped: (s, precision=4) ->
    ast = require("parsing/expression").parse(s)
    
    pad = (s, length) ->
      spaces = (n) -> [0 ... n].map(() -> " ").join("")
      n = length - s.length
      # spaces(Math.ceil(n/2)) + s + spaces(Math.floor(n/2))
      s + spaces(n)
    
    step = (tree) ->
      # takes a tree and returns a new tree, simplified one step
      ret = []
      didReduction = false
      for node in tree
        if !didReduction && _.isArray(node)
          ret.push(step(node))
          didReduction = true
        else
          ret.push(node)
      if !didReduction
        joined = tree.join("")
        evaled = evalInContext(joined).toFixed(precision)
        return evaled
        # return pad(evaled, joined.length)
      else
        return ret
    
    ret = []
    while _.isArray(ast)
      ret.push(_.flatten(ast).join(""))
      ast = step(ast)
    ret.push(ast.toString())
    
    return ret
  
  findSubExpression: (s, cStart, cEnd) ->
    # Take an expression and a character or selection, find the smallest subexpression that contains x and that selection
    # returns the start character and length of the subexpression
    tree = require("parsing/expression").parse(s)
    
    
    sum = (a) ->
      _.reduce(a, ((memo, num) -> memo + num), 0)
    
    length = (tree) ->
      if _.isArray(tree)
        return sum(_.map(tree, length))
      else
        return tree.length
    
    find = (tree, start=0) ->
      s = start
      found = [s, length(tree)]
      for node in tree
        if s > cStart
          # gone too far
          break
        if s + length(node) < cEnd
          # too short, keep looking
          s += length(node)
        else
          # ok, we contain cStart and cEnd
          if _.isArray(node) && hasX(node)
            # we found a good subexpression, recurse
            found = find(node, s)
          else
            # we've gone too deep
            break
      return found
    
    return find(tree)
  
  findAllSubExpressions: (s) ->
    tree = require("parsing/expression").parse(s)
    
    subExprs = []
    
    spider = (tree) ->
      if _.isArray(tree)
        if hasX(tree)
          subExprs.push(tree)
        for node in tree
          spider(node)
    spider(tree)
    
    return subExprs
}

module.exports = evaluate