_ = require 'underscore-plus'
{Range} = require 'atom'

Base = require './base'
swrap = require './selection-wrapper'

class VisualBlockwise extends Base
  @extend()
  complete: true

  constructor: ->
    super
    @initialize?()
  
  initialize: ->
    # PlantTail
    unless @getTail()?
      @updateProperties {head: @getBottom(), tail: @getTop()}

  eachSelection: (fn) ->
    for s in @editor.getSelections()
      fn(s)

  countTimes: (fn) ->
    _.times @getCount(), ->
      fn()

  updateProperties: ({head, tail}) ->
    @eachSelection (s) ->
      prop = {}
      prop.head = (s is head) if head?
      prop.tail = (s is tail) if tail?
      swrap(s).updateProperties(blockwise: prop)

  isSingleLine: ->
    @editor.getSelections().length is 1

  getTop: ->
    @editor.getSelectionsOrderedByBufferPosition()[0]

  getBottom: ->
    _.last @editor.getSelectionsOrderedByBufferPosition()

  isReversed: ->
    (not @isSingleLine()) and @getTail() is @getBottom()

  getHead: ->
    if @isReversed() then @getTop() else @getBottom()

  getTail: ->
    _.detect @editor.getSelections(), (s) -> swrap(s).isBlockwiseTail()

  getBufferRowRange: ->
    startRow = @getTop().getBufferRowRange()[0]
    endRow = @getBottom().getBufferRowRange()[0]
    [startRow, endRow]

class BlockwiseOtherEnd extends VisualBlockwise
  @extend()
  execute: ->
    unless @isSingleLine()
      @updateProperties {head: @getTail(), tail: @getHead()}
    @new('ReverseSelections').execute()

class BlockwiseMoveDown extends VisualBlockwise
  @extend()
  direction: 'Below'

  isExpanding: ->
    return true if @isSingleLine()
    switch @direction
      when 'Below' then not @isReversed()
      when 'Above' then @isReversed()

  execute: ->
    @countTimes =>
      if @isExpanding()
        @editor["addSelection#{@direction}"]()
        swrap.setReversedState @editor, @getTail().isReversed()
      else
        @getHead().destroy()
    @updateProperties {head: @getHead()}

class BlockwiseMoveUp extends BlockwiseMoveDown
  @extend()
  direction: 'Above'

class BlockwiseDeleteToLastCharacterOfLine extends VisualBlockwise
  @extend()
  delegateTo: 'DeleteToLastCharacterOfLine'

  initialize: ->
    @operator = @new(@delegateTo)

  execute: ->
    @eachSelection (s) ->
      s.cursor.setBufferPosition s.getBufferRange().start
    finalPoint = @getTop().cursor.getBufferPosition()
    @vimState.activate('normal')
    @operator.execute()
    @editor.clearSelections()
    @editor.setCursorBufferPosition finalPoint

class BlockwiseChangeToLastCharacterOfLine extends BlockwiseDeleteToLastCharacterOfLine
  @extend()
  recordable: true
  delegateTo: 'ChangeToLastCharacterOfLine'

  getCheckpoint: ->
    @operator.getCheckpoint()

  initialize: ->
    @operator = @new(@delegateTo)

class BlockwiseInsertAtBeginningOfLine extends VisualBlockwise
  @extend()
  delegateTo: 'ActivateInsertMode'
  recordable: true
  after: false

  getCheckpoint: ->
    @operator.getCheckpoint()

  initialize: ->
    @operator = @new(@delegateTo)

  execute: ->
    which = if @after then 'end' else 'start'
    @eachSelection (s) ->
      s.cursor.setBufferPosition s.getBufferRange()[which]

    # FIXME confirmChanges is not called when deactivate insert-mode.
    @operator.execute()

class BlockwiseInsertAfterEndOfLine extends BlockwiseInsertAtBeginningOfLine
  @extend()
  after: true

class BlockwiseSelect extends VisualBlockwise
  @extend(false)
  execute: ->
    selection = @editor.getLastSelection()
    wasReversed = reversed = selection.isReversed()
    {start, end} = selection.getScreenRange()
    startColumn = start.column
    endColumn = end.column

    if startColumn >= endColumn
      reversed = not reversed
      startColumn += 1
      endColumn -= 1

    ranges = ([[row, startColumn], [row, endColumn]] for row in [start.row..end.row])
    # If selection is single line we don't need to add selection to save other mult-selection
    # This tweeking allow find-and-replace:select-next then ctrl-v, I(or A) flow work.
    unless selection.isSingleScreenLine()
      @editor.setSelectedScreenRanges(ranges, {reversed})
    if wasReversed
      @updateProperties {head: @getTop(), tail: @getBottom()}
    else
      @updateProperties {head: @getBottom(), tail: @getTop()}
    @eachSelection (s) ->
      s.destroy() if s.isEmpty()

class BlockwiseRestoreCharacterwise extends VisualBlockwise
  @extend(false)

  execute: ->
    reversed = @isReversed()
    head = @getHead()
    headIsReversed = head.isReversed()
    [startRow, endRow] = @getBufferRowRange()
    {start: {column: startColumn}, end: {column: endColumn}} = head.getBufferRange()
    if reversed isnt headIsReversed
      [startColumn, endColumn] = [endColumn, startColumn]
      startColumn -= 1
      endColumn += 1
    range = [[startRow, startColumn], [endRow, endColumn]]
    @editor.setSelectedBufferRange(range, {reversed})
