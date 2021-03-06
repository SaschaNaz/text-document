Point = require "./point"
Range = require "./range"
{addSet, subtractSet, intersectSet, setEqual} = require "./set-helpers"

# Max number of children allowed in a Node
BRANCHING_THRESHOLD = 3

class Node
  constructor: (@children) ->
    @ids = new Set
    @extent = Point.zero()
    for child in @children
      @extent = @extent.traverse(child.extent)
      addSet(@ids, child.ids)

  insert: (ids, start, end) ->
    rangeIsEmpty = start.compare(end) is 0
    childEnd = Point.zero()
    i = 0
    while i < @children.length
      child = @children[i++]
      childStart = childEnd
      childEnd = childStart.traverse(child.extent)

      switch childEnd.compare(start)
        when -1 then childPrecedesRange = true
        when 1  then childPrecedesRange = false
        when 0
          if child.hasEmptyRightmostLeaf()
            childPrecedesRange = false
          else
            childPrecedesRange = true
            if rangeIsEmpty
              ids = new Set(ids)
              child.findContaining(child.extent, ids)
      continue if childPrecedesRange

      switch childStart.compare(end)
        when -1 then childFollowsRange = false
        when 1  then childFollowsRange = true
        when 0  then childFollowsRange = not (child.hasEmptyLeftmostLeaf() or rangeIsEmpty)
      break if childFollowsRange

      relativeStart = Point.max(Point.zero(), start.traversalFrom(childStart))
      relativeEnd = Point.min(child.extent, end.traversalFrom(childStart))
      if newChildren = child.insert(ids, relativeStart, relativeEnd)
        @children.splice(i - 1, 1, newChildren...)
        i += newChildren.length - 1
      break if rangeIsEmpty

    if @children.length > BRANCHING_THRESHOLD
      splitIndex = Math.ceil(@children.length / BRANCHING_THRESHOLD)
      [new Node(@children.slice(0, splitIndex)), new Node(@children.slice(splitIndex))]
    else
      addSet(@ids, ids)
      return

  delete: (id) ->
    return unless @ids.delete(id)
    i = 0
    while i < @children.length
      @children[i].delete(id)
      if @children[i - 1]?.shouldMergeWith(@children[i])
        @children.splice(i - 1, 2, @children[i - 1].merge(@children[i]))
      else
        i++

  splice: (position, oldExtent, newExtent, excludedIds) ->
    oldRangeIsEmpty = oldExtent.isZero()
    childEnd = Point.zero()
    for child in @children
      childStart = childEnd
      childEnd = childStart.traverse(child.extent)

      if remainderToDelete?
        remainderToDelete = child.splice(Point.zero(), remainderToDelete, Point.zero())
        continue

      switch childEnd.compare(position)
        when -1 then childPrecedesRange = true
        when 0  then childPrecedesRange = not (child.hasEmptyRightmostLeaf() and oldRangeIsEmpty)
        when 1  then childPrecedesRange = false
      continue if childPrecedesRange

      relativeStart = position.traversalFrom(childStart)
      remainderToDelete = child.splice(relativeStart, oldExtent, newExtent, excludedIds)

    @extent = @extent
      .traverse(newExtent.traversalFrom(oldExtent))
      .traverse(remainderToDelete)
    remainderToDelete

  getStart: (id) ->
    return unless @ids.has(id)
    childEnd = Point.zero()
    for child in @children
      childStart = childEnd
      childEnd = childStart.traverse(child.extent)
      if startRelativeToChild = child.getStart(id)
        return childStart.traverse(startRelativeToChild)
    return

  getEnd: (id) ->
    return unless @ids.has(id)
    childEnd = Point.zero()
    for child in @children
      childStart = childEnd
      childEnd = childStart.traverse(child.extent)
      if endRelativeToChild = child.getEnd(id)
        end = childStart.traverse(endRelativeToChild)
      else if end?
        break
    end

  findContaining: (point, set) ->
    childEnd = Point.zero()
    for child in @children
      childStart = childEnd
      childEnd = childStart.traverse(child.extent)
      continue if childEnd.compare(point) < 0
      break if childStart.compare(point) > 0
      child.findContaining(point.traversalFrom(childStart), set)

  findIntersecting: (start, end, set) ->
    if start.isZero() and end.compare(@extent) is 0
      addSet(set, @ids)
      return

    childEnd = Point.zero()
    for child in @children
      childStart = childEnd
      childEnd = childStart.traverse(child.extent)
      continue if childEnd.compare(start) < 0
      break if childStart.compare(end) > 0
      child.findIntersecting(
        Point.max(Point.zero(), start.traversalFrom(childStart)),
        Point.min(child.extent, end.traversalFrom(childStart)),
        set
      )

  hasEmptyRightmostLeaf: ->
    @children[@children.length - 1].hasEmptyRightmostLeaf()

  hasEmptyLeftmostLeaf: ->
    @children[0].hasEmptyLeftmostLeaf()

  shouldMergeWith: (other) ->
    @children.length + other.children.length <= BRANCHING_THRESHOLD

  merge: (other) ->
    new Node(@children.concat(other.children))

  toString: (indentLevel=0) ->
    indent = ""
    indent += " " for i in [0...indentLevel] by 1

    ids = []
    values = @ids.values()
    until (next = values.next()).done
      ids.push(next.value)

    """
      #{indent}Node #{@extent} (#{ids.join(" ")})
      #{@children.map((c) -> c.toString(indentLevel + 2)).join("\n")}
    """

class Leaf
  constructor: (@extent, @ids) ->

  insert: (ids, start, end) ->
    # If the given range matches the start and end of this leaf exactly, add
    # the given id to this leaf. Otherwise, split this leaf into up to 3 leaves,
    # adding the id to the portion of this leaf that intersects the given range.
    if start.isZero() and end.compare(@extent) is 0
      addSet(@ids, ids)
      return
    else
      newIds = new Set(@ids)
      addSet(newIds, ids)
      newLeaves = []
      newLeaves.push(new Leaf(start, new Set(@ids))) if start.isPositive()
      newLeaves.push(new Leaf(end.traversalFrom(start), newIds))
      newLeaves.push(new Leaf(@extent.traversalFrom(end), new Set(@ids))) if @extent.compare(end) > 0
      newLeaves

  delete: (id) ->
    @ids.delete(id)

  splice: (position, spliceOldExtent, spliceNewExtent, excludedIds) ->
    subtractSet(@ids, excludedIds) if excludedIds?
    myOldExtent = @extent
    spliceOldEnd = position.traverse(spliceOldExtent)
    spliceNewEnd = position.traverse(spliceNewExtent)
    spliceDelta = spliceNewExtent.traversalFrom(spliceOldExtent)

    if spliceOldEnd.compare(@extent) > 0
      # If the splice ends after this leaf node, this leaf should end at
      # the end of the splice.
      @extent = spliceNewEnd
    else
      # Otherwise, this leaf contains the splice, its size should be adjusted
      # by the delta.
      @extent = Point.max(Point.zero(), @extent.traverse(spliceDelta))

    # How does the splice to this leaf's extent compare to the global splice in
    # the tree's extent implied by the splice? If this leaf grew too much or didn't
    # shrink enough, we may need to shrink subsequent leaves.
    @extent.traversalFrom(myOldExtent).traversalFrom(spliceDelta)

  getStart: (id) ->
    Point.zero() if @ids.has(id)

  getEnd: (id) ->
    @extent if @ids.has(id)

  findContaining: (point, set) ->
    addSet(set, @ids)

  findIntersecting: (start, end, set) ->
    addSet(set, @ids)

  hasEmptyRightmostLeaf: ->
    @extent.isZero()

  hasEmptyLeftmostLeaf: ->
    @extent.isZero()

  shouldMergeWith: (other) ->
    setEqual(@ids, other.ids)

  merge: (other) ->
    new Leaf(@extent.traverse(other.extent), new Set(@ids))

  toString: (indentLevel=0) ->
    indent = ""
    indent += " " for i in [0...indentLevel] by 1

    ids = []
    values = @ids.values()
    until (next = values.next()).done
      ids.push(next.value)

    "#{indent}Leaf #{@extent} (#{ids.join(" ")})"

module.exports =
class MarkerIndex
  constructor: ->
    @exclusiveIds = new Set
    @rootNode = new Leaf(Point.infinity(), new Set)

  insert: (id, start, end) ->
    if splitNodes = @rootNode.insert(new Set().add(id), start, end)
      @rootNode = new Node(splitNodes)

  delete: (id) ->
    @rootNode.delete(id)

  splice: (position, oldExtent, newExtent) ->
    if oldExtent.isZero()
      startingIds = @findStartingIn(position)
      endingIds = @findEndingIn(position)
      addSet(startingIds, endingIds)
      boundaryIds = startingIds

      if boundaryIds.size > 0
        if splitNodes = @rootNode.insert(boundaryIds, position, position)
          @rootNode = new Node(splitNodes)

        excludedIds = new Set
        boundaryIds.forEach (id) =>
          excludedIds.add(id) if @exclusiveIds.has(id)

    @rootNode.splice(position, oldExtent, newExtent, excludedIds)

  setExclusive: (id, isExclusive) ->
    if isExclusive
      @exclusiveIds.add(id)
    else
      @exclusiveIds.delete(id)

  getRange: (id) ->
    if start = @getStart(id)
      Range(start, @getEnd(id))

  getStart: (id) ->
    @rootNode.getStart(id)

  getEnd: (id) ->
    @rootNode.getEnd(id)

  findContaining: (start, end) ->
    containing = new Set
    @rootNode.findContaining(start, containing)
    if end? and end.compare(start) isnt 0
      containingEnd = new Set
      @rootNode.findContaining(end, containingEnd)
      containing.forEach (id) -> containing.delete(id) unless containingEnd.has(id)
    containing

  findContainedIn: (start, end = start) ->
    result = @findStartingIn(start, end)
    subtractSet(result, @findIntersecting(end.traverse(Point(0, 1))))
    result

  findIntersecting: (start, end = start) ->
    intersecting = new Set
    @rootNode.findIntersecting(start, end, intersecting)
    intersecting

  findStartingIn: (start, end = start) ->
    result = @findIntersecting(start, end)
    if start.isPositive()
      if start.column is 0
        previousPoint = Point(start.row - 1, Infinity)
      else
        previousPoint = Point(start.row, start.column - 1)
      subtractSet(result, @findIntersecting(previousPoint))
    result

  findEndingIn: (start, end = start) ->
    result = @findIntersecting(start, end)
    subtractSet(result, @findIntersecting(end.traverse(Point(0, 1))))
    result
