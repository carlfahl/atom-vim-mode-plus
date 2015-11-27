# Refactoring status: 95%
{Range} = require 'atom'
_    = require 'underscore-plus'

Base = require './base'
swrap = require './selection-wrapper'
{
  isLinewiseRange
  rangeToBeginningOfFileFromPoint
  rangeToEndOfFileFromPoint
  sortRanges
  getLineTextToPoint
} = require './utils'

class TextObject extends Base
  @extend(false)
  complete: true
  inner: false

  constructor: ->
    super
    @initialize?()

  isInner: ->
    @inner

  isLinewise: ->
    @editor.getSelections().every (s) ->
      isLinewiseRange(s.getBufferRange())

  eachSelection: (fn) ->
    fn(s) for s in @editor.getSelections()
    return if @vimState.isMode('operator-pending')
    return if @vimState.isMode('visual', 'linewise')
    if @isLinewise()
      @vimState.activate('visual', 'linewise')

  execute: ->
    @select()

# Word
# -------------------------
# [FIXME] Need to be extendable.
class Word extends TextObject
  @extend()
  select: ->
    @eachSelection (selection) =>
      wordRegex = @wordRegExp ? selection.cursor.wordRegExp()
      @selectExclusive(selection, wordRegex)
      @selectInclusive(selection) unless @isInner()

  selectExclusive: (selection, wordRegex=null) ->
    selection.selectWord()

  selectInclusive: (selection) ->
    scanRange = selection.cursor.getCurrentLineBufferRange()
    headPoint = selection.getHeadBufferPosition()
    scanRange.start = headPoint
    @editor.scanInBufferRange /\s+/, scanRange, ({range, stop}) ->
      if headPoint.isEqual(range.start)
        selection.selectToBufferPosition range.end
        stop()

class WholeWord extends Word
  @extend()
  wordRegExp: /\S+/
  selectExclusive: (s, wordRegex) ->
    swrap(s).setBufferRangeSafely s.cursor.getCurrentWordBufferRange({wordRegex})

# Pair
# -------------------------
class Pair extends TextObject
  @extend(false)
  allowNextLine: false
  what: 'enclosed'
  pair: null

  # Return 'open' or 'close'
  getPairState: (pair, matchText, point) ->
    [openChar, closeChar] = pair.split('')
    if openChar is closeChar
      text = getLineTextToPoint(@editor, point)
      state = @pairStateInString(text, openChar)
    else
      state =
        switch pair.indexOf(matchText[matchText.length-1])
          when 0 then 'open'
          when 1 then 'close'
    state

  pairStateInString: (str, char) ->
    pattern = ///[^\\]?#{_.escapeRegExp(char)}///
    count = str.split(pattern).length - 1
    switch count % 2
      when 1 then 'open'
      when 0 then 'close'

  # Take start point of matched range.
  escapeChar = '\\'
  isEscapedCharAtPoint: (point) ->
    range = Range.fromPointWithDelta(point, 0, -1)
    @editor.getTextInBufferRange(range) is escapeChar

  findPair: (pair, options) ->
    {from, which, allowNextLine, nest} = options
    [scanFunc, scanRange] =
      switch which
        when 'open' then ['backwardsScanInBufferRange', rangeToBeginningOfFileFromPoint(from)]
        when 'close' then ['scanInBufferRange', rangeToEndOfFileFromPoint(from)]
    pairRegexp = pair.split('').map(_.escapeRegExp).join('|')
    pattern = ///#{pairRegexp}///g

    found = null # We will search to fill this var.
    @editor[scanFunc] pattern, scanRange, (arg) =>
      {matchText, range, stop} = arg
      {start, end} = range
      return if @isEscapedCharAtPoint(start)
      return stop() if (not allowNextLine) and (from.row isnt start.row)

      if which is 'close'
        end = end.translate([0, -1])
      if @getPairState(pair, matchText, start) is which
        nest = Math.max(nest-1, 0)
      else
        nest++
      if nest is 0
        found = end
        stop()
    found

  getPairRange: (from, pair, what) ->
    range = null
    switch what
      when 'enclosed'
        open  = @findPair pair, {from,       @allowNextLine, nest: 1, which: 'open'}
        close = @findPair pair, {from: open, @allowNextLine, nest: 1, which: 'close'} if open?
      when 'next'
        close = @findPair pair, {from,        @allowNextLine, nest: 0, which: 'close'}
        open  = @findPair pair, {from: close, @allowNextLine, nest: 1, which: 'open'} if close?
      when 'previous' # FIXME but currently unused
        open  = @findPair pair, {from,       @allowNextLine, nest: 0, which: 'open'}
        close = @findPair pair, {from: open, @allowNextLine, nest: 1, which: 'close'} if open?
    if open and close
      range = new Range(open, close)
      range = range.translate([0, -1], [0, 1]) unless @isInner()
    range

  getRange: (selection, what=@what) ->
    rangeOrig = selection.getBufferRange()
    from = selection.getHeadBufferPosition()

    # Be inner, include char under cursor.
    from = from.translate([0, +1]) if selection.isEmpty()
    from = from.translate([0, -1]) if what is 'next'

    range  = @getPairRange(from, @pair, what)
    if range?.isEqual(rangeOrig)
      # Since range was same area, retry to expand outer pair.
      switch what
        when 'enclosed', 'previous'
          from = range.start.translate([0, -1])
        when 'next'
          from = range.end.translate([0, +1])
      range = @getPairRange(from, @pair, what)
    range

  select: ->
    @eachSelection (s) =>
      swrap(s).setBufferRangeSafely @getRange(s, @what)

class AnyPair extends Pair
  @extend()
  what: 'enclosed'
  member: [
    'DoubleQuote', 'SingleQuote', 'BackTick',
    'CurlyBracket', 'AngleBracket', 'Tag', 'SquareBracket', 'Parenthesis'
  ]

  getRangeBy: (klass, selection) ->
    # overwite default @what
    @new(klass, {@inner}).getRange(selection, @what)

  getRanges: (selection) ->
    ranges = []
    for klass in @member when (range = @getRangeBy(klass, selection))
      ranges.push range
    ranges

  getNearestRange: (selection) ->
    ranges = @getRanges(selection)
    _.last(sortRanges(ranges)) if ranges.length

  select: ->
    @eachSelection (s) =>
      swrap(s).setBufferRangeSafely @getNearestRange(s)

class AnyQuote extends AnyPair
  @extend()
  what: 'next'
  member: ['DoubleQuote', 'SingleQuote', 'BackTick']
  getNearestRange: (selection) ->
    ranges = @getRanges(selection)
    # Pick range which end.colum is leftmost(mean, closed first)
    _.first(_.sortBy(ranges, (r) -> r.end.column)) if ranges.length

class DoubleQuote extends Pair
  @extend()
  pair: '""'
  what: 'next'

class SingleQuote extends Pair
  @extend()
  pair: "''"
  what: 'next'

class BackTick extends Pair
  @extend()
  pair: '``'
  what: 'next'

class CurlyBracket extends Pair
  @extend()
  pair: '{}'
  allowNextLine: true

class SquareBracket extends Pair
  @extend()
  pair: '[]'
  allowNextLine: true

class Parenthesis extends Pair
  @extend()
  pair: '()'
  allowNextLine: true

class AngleBracket extends Pair
  @extend()
  pair: '<>'

# [FIXME] See vim-mode#795
class Tag extends Pair
  @extend()
  pair: '><'

# Paragraph
# -------------------------
# In Vim world Paragraph is defined as consecutive (non-)blank-line.
class Paragraph extends TextObject
  @extend()

  getStartRow: (startRow, fn) ->
    for row in [startRow..0] when fn(row)
      return row+1
    0

  getEndRow: (startRow, fn) ->
    lastRow = @editor.getLastBufferRow()
    for row in [startRow..lastRow] when fn(row)
      return row
    lastRow+1

  getRange: (startRow) ->
    startRowIsBlank = @editor.isBufferRowBlank(startRow)
    fn = (row) =>
      @editor.isBufferRowBlank(row) isnt startRowIsBlank
    new Range([@getStartRow(startRow, fn), 0], [@getEndRow(startRow, fn), 0])

  selectParagraph: (selection) ->
    [startRow, endRow] = selection.getBufferRowRange()
    if startRow is endRow
      swrap(selection).setBufferRangeSafely @getRange(startRow)
    else # have direction
      if selection.isReversed()
        if range = @getRange(startRow-1)
          selection.selectToBufferPosition range.start
      else
        if range = @getRange(endRow+1)
          selection.selectToBufferPosition range.end

  selectExclusive: (selection) ->
    @selectParagraph(selection)

  selectInclusive: (selection) ->
    @selectParagraph(selection)
    @selectParagraph(selection)

  select: ->
    @eachSelection (selection) =>
      _.times @getCount(), =>
        if @isInner()
          @selectExclusive(selection)
        else
          @selectInclusive(selection)

class Comment extends Paragraph
  @extend()
  selectInclusive: (selection) ->
    @selectParagraph(selection)

  getRange: (startRow) ->
    return unless @editor.isBufferRowCommented(startRow)
    fn = (row) =>
      return if (not @isInner() and @editor.isBufferRowBlank(row))
      @editor.isBufferRowCommented(row) in [false, undefined]
    new Range([@getStartRow(startRow, fn), 0], [@getEndRow(startRow, fn), 0])

class Indentation extends Paragraph
  @extend()
  selectInclusive: (selection) ->
    @selectParagraph(selection)

  getRange: (startRow) ->
    return if @editor.isBufferRowBlank(startRow)
    text = @editor.lineTextForBufferRow(startRow)
    baseIndentLevel = @editor.indentLevelForLine(text)
    fn = (row) =>
      if @editor.isBufferRowBlank(row)
        @isInner()
      else
        text = @editor.lineTextForBufferRow(row)
        @editor.indentLevelForLine(text) < baseIndentLevel
    new Range([@getStartRow(startRow, fn), 0], [@getEndRow(startRow, fn), 0])

# TODO: make it extendable when repeated
class Fold extends TextObject
  @extend()
  getFoldRowRangeForBufferRow: (bufferRow) ->
    for currentRow in [bufferRow..0] by -1
      [startRow, endRow] = @editor.languageMode.rowRangeForCodeFoldAtBufferRow(currentRow) ? []
      continue unless startRow? and startRow <= bufferRow <= endRow
      startRow += 1 if @isInner()
      return [startRow, endRow]

  select: ->
    @eachSelection (selection) =>
      [startRow, endRow] = selection.getBufferRowRange()
      row = if selection.isReversed() then startRow else endRow
      if rowRange = @getFoldRowRangeForBufferRow(row)
        swrap(selection).selectRowRange(rowRange)

# NOTE: Function range determination is depending on fold.
class Function extends Fold
  @extend()

  indentScopedLanguages: ['python', 'coffee']
  # FIXME: why go dont' fold closing '}' for function? this is dirty workaround.
  omitingClosingCharLanguages: ['go']

  initialize: ->
    @language = @editor.getGrammar().scopeName.replace(/^source\./, '')

  getScopesForRow: (row) ->
    tokenizedLine = @editor.displayBuffer.tokenizedBuffer.tokenizedLineForRow(row)
    for tag in tokenizedLine.tags when tag < 0 and (tag % 2 is -1)
      atom.grammars.scopeForId(tag)

  isFunctionScope: (scope) ->
    regex = if @language in ['go']
      /^entity.name.function/
    else
      /^meta.function/
    regex.test(scope)

  isIncludeFunctionScopeForRow: (row) ->
    for scope in @getScopesForRow(row) when @isFunctionScope(scope)
      return true
    null

  # Greatly depending on fold, and what range is folded is vary from languages.
  # So we need to adjust endRow based on scope.
  getFoldRowRangeForBufferRow: (bufferRow) ->
    for currentRow in [bufferRow..0] by -1
      [startRow, endRow] = @editor.languageMode.rowRangeForCodeFoldAtBufferRow(currentRow) ? []
      unless startRow? and (startRow <= bufferRow <= endRow) and @isIncludeFunctionScopeForRow(startRow)
        continue
      return @adjustRowRange(startRow, endRow)
    null

  adjustRowRange: (startRow, endRow) ->
    if @isInner()
      startRow += 1
      unless @language in @indentScopedLanguages
        endRow -= 1
    endRow += 1 if (@language in @omitingClosingCharLanguages)
    [startRow, endRow]

class CurrentLine extends TextObject
  @extend()
  select: ->
    @eachSelection (selection) =>
      {cursor} = selection
      cursor.moveToBeginningOfLine()
      cursor.moveToFirstCharacterOfLine() if @isInner()
      selection.selectToEndOfLine()

class Entire extends TextObject
  @extend()
  select: ->
    @editor.selectAll()
