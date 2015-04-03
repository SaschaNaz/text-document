class Checkpoint

module.exports =
class History
  constructor: ->
    @undoStack = []
    @redoStack = []

  createCheckpoint: ->
    checkpoint = new Checkpoint
    @undoStack.push(checkpoint)
    checkpoint

  groupChangesSinceCheckpoint: (checkpoint) ->
    for entry, i in @undoStack by -1
      break if entry is checkpoint
      @undoStack.splice(i, 1) if entry instanceof Checkpoint

  applyCheckpointGroupingInterval: (checkpoint, groupingInterval) ->
    return if groupingInterval is 0

    now = Date.now()

    groupedCheckpoint = null
    checkpointIndex = @undoStack.lastIndexOf(checkpoint)

    for i in [checkpointIndex - 1..0] by -1
      entry = @undoStack[i]
      if entry instanceof Checkpoint
        if (entry.timestamp + Math.min(entry.groupingInterval, groupingInterval)) >= now
          @undoStack.splice(checkpointIndex, 1)
          groupedCheckpoint = entry
        else
          groupedCheckpoint = checkpoint
        break

    groupedCheckpoint.timestamp = now
    groupedCheckpoint.groupingInterval = groupingInterval

  pushChange: (change) ->
    @undoStack.push(new Checkpoint, change)
    @redoStack.length = 0

  popUndoStack: ->
    invertedChanges = []
    while entry = @undoStack.pop()
      @redoStack.push(entry)
      if entry instanceof Checkpoint
        break if invertedChanges.length > 0
      else
        invertedChanges.push(@invertChange(entry))
    invertedChanges

  truncateUndoStack: (checkpoint) ->
    invertedChanges = []
    while entry = @undoStack.pop()
      if entry instanceof Checkpoint
        break if entry is checkpoint
      else
        invertedChanges.push(@invertChange(entry))
    invertedChanges

  popRedoStack: ->
    changes = []
    while entry = @redoStack.pop()
      if entry instanceof Checkpoint
        if changes.length > 0
          @redoStack.push(entry)
          break
      else
        changes.push(entry)
      @undoStack.push(entry)
    changes

  clearRedoStack: ->
    @redoStack.length = 0

  invertChange: ({oldRange, newRange, oldText, newText}) ->
    Object.freeze({
      oldRange: newRange
      newRange: oldRange
      oldText: newText
      newText: oldText
    })
