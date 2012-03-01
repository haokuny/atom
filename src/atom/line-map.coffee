_ = require 'underscore'
Point = require 'point'
Range = require 'range'

module.exports =
class LineMap
  constructor: ->
    @lineFragments = []

  insertAtBufferRow: (bufferRow, lineFragments) ->
    @spliceAtBufferRow(bufferRow, 0, lineFragments)

  spliceAtBufferRow: (startRow, rowCount, lineFragments) ->
    @spliceByDelta('bufferDelta', startRow, rowCount, lineFragments)

  spliceAtScreenRow: (startRow, rowCount, lineFragments) ->
    @spliceByDelta('screenDelta', startRow, rowCount, lineFragments)

  replaceBufferRows: (start, end, lineFragments) ->
    @spliceAtBufferRow(start, end - start + 1, lineFragments)

  replaceScreenRow: (row, lineFragments) ->
    @replaceScreenRows(row, row, lineFragments)

  replaceScreenRows: (start, end, lineFragments) ->
    @spliceAtScreenRow(start, end - start + 1, lineFragments)

  lineForScreenRow: (row) ->
    @linesForScreenRows(row, row)[0]

  linesForScreenRows: (startRow, endRow) ->
    @linesByDelta('screenDelta', startRow, endRow)

  lineForBufferRow: (row) ->
    @linesForBufferRows(row, row)[0]

  linesForBufferRows: (startRow, endRow) ->
    @linesByDelta('bufferDelta', startRow, endRow)

  bufferLineCount: ->
    @bufferPositionForScreenPosition([Infinity, 0]).row

  screenLineCount: ->
    @screenPositionForBufferPosition([Infinity, 0]).row

  lastScreenRow: ->
    @screenLineCount() - 1

  screenPositionForBufferPosition: (bufferPosition) ->
    @translatePosition('bufferDelta', 'screenDelta', bufferPosition)

  bufferPositionForScreenPosition: (screenPosition) ->
    @translatePosition('screenDelta', 'bufferDelta', screenPosition)

  screenRangeForBufferRange: (bufferRange) ->
    start = @screenPositionForBufferPosition(bufferRange.start)
    end = @screenPositionForBufferPosition(bufferRange.end)
    new Range(start, end)

  bufferRangeForScreenRange: (screenRange) ->
    start = @bufferPositionForScreenPosition(screenRange.start)
    end = @bufferPositionForScreenPosition(screenRange.end)
    new Range(start, end)

  clipScreenPosition: (screenPosition, options) ->
    screenPosition = Point.fromObject(screenPosition)
    maxScreenRow = @lastScreenRow()
    if screenPosition.row > maxScreenRow
      screenPosition.row = maxScreenRow
      screenPosition.column = Infinity

    @translatePosition('screenDelta', 'screenDelta', screenPosition, options)

  spliceByDelta: (deltaType, startRow, rowCount, lineFragments) ->
    stopRow = startRow + rowCount
    startIndex = undefined
    stopIndex = 0

    delta = new Point
    for lineFragment, i in @lineFragments
      startIndex ?= i if delta.row == startRow
      break if rowCount == 0 and delta.row == stopRow
      delta = delta.add(lineFragment[deltaType])
      break if delta.row > stopRow
      stopIndex++
    startIndex ?= i

    @lineFragments[startIndex...stopIndex] = lineFragments

  linesByDelta: (deltaType, startRow, endRow) ->
    lines = []
    pendingFragment = null
    @traverseByDelta deltaType, new Point(startRow, 0), new Point(endRow, Infinity), (lineFragment) ->
      if pendingFragment
        pendingFragment = pendingFragment.concat(lineFragment)
      else
        pendingFragment = _.clone(lineFragment)
      if pendingFragment[deltaType].row > 0
        pendingFragment.bufferDelta = new Point(1, 0)
        lines.push pendingFragment
        pendingFragment = null
    lines

  translatePosition: (sourceDeltaType, targetDeltaType, sourcePosition, options={}) ->
    sourcePosition = Point.fromObject(sourcePosition)
    wrapBeyondNewlines = options.wrapBeyondNewlines ? false
    wrapAtSoftNewlines = options.wrapAtSoftNewlines ? false
    skipAtomicTokens = options.skipAtomicTokens ? false

    if sourcePosition.column < 0
      sourcePosition.column = 0

    if sourcePosition.row < 0
      sourcePosition.row = 0
      sourcePosition.column = 0

    traversalResult = @traverseByDelta(sourceDeltaType, sourcePosition)
    lastLineFragment = traversalResult.lastLineFragment
    sourceDelta = traversalResult[sourceDeltaType]
    targetDelta = traversalResult[targetDeltaType]

    if lastLineFragment.isAtomic
      if skipAtomicTokens and sourcePosition.column > sourceDelta.column
        return new Point(targetDelta.row, targetDelta.column + lastLineFragment.text.length)
      else
        return targetDelta

    maxSourceColumn = sourceDelta.column + lastLineFragment.text.length
    maxTargetColumn = targetDelta.column + lastLineFragment.text.length
    if lastLineFragment.isSoftWrapped() and sourcePosition.column >= maxSourceColumn
      if wrapAtSoftNewlines
        return new Point(targetDelta.row + 1, 0)
      else
        return new Point(targetDelta.row, maxTargetColumn - 1)

    if sourcePosition.column > maxSourceColumn and wrapBeyondNewlines
      return new Point(targetDelta.row + 1, 0)

    targetColumn = targetDelta.column + (sourcePosition.column - sourceDelta.column)
    new Point(targetDelta.row, Math.min(maxTargetColumn, targetColumn))

  traverseByDelta: (deltaType, startPosition, endPosition=startPosition, iterator=null) ->
    traversalDelta = new Point
    screenDelta = new Point
    bufferDelta = new Point

    for lineFragment in @lineFragments
      iterator(lineFragment) if traversalDelta.isGreaterThanOrEqual(startPosition) and iterator?
      traversalDelta = traversalDelta.add(lineFragment[deltaType])
      break if traversalDelta.isGreaterThan(endPosition)
      screenDelta = screenDelta.add(lineFragment.screenDelta)
      bufferDelta = bufferDelta.add(lineFragment.bufferDelta)

    { screenDelta, bufferDelta, lastLineFragment: lineFragment }

  logLines: (start=0, end=@screenLineCount() - 1)->
    for row in [start..end]
      line = @lineForScreenRow(row).text
      console.log row, line, line.length

