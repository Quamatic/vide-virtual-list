local vide = require(script.Parent.Parent.vide)
type Source<T> = vide.Source<T>

local store = require(script.Parent.store)
local createVirtualStore = store.createVirtualStore

local scroller = require(script.Parent.scroller)
local createScroller = scroller.createScroller

local types = require(script.Parent.types)
type ScrollAnimator = types.ScrollAnimator
type ScrollToIndexParams = types.ScrollToIndexParams

local VirtualStoreAction = require(script.Parent.VirtualStoreAction)
local VirtualStoreSubscription = require(script.Parent.VirtualStoreSubscription)

local RangedFor = require(script.RangedFor)
local ListItem = require(script.ListItem)

local create = vide.create
local source = vide.source
local derive = vide.derive
local effect = vide.effect
local action = vide.action
local changed = vide.changed
local cleanup = vide.cleanup

export type VirtualListHandle = {
	scrollOffset: () -> number,
	--scrollSize: () -> number,
	viewportSize: () -> number,
	findStartIndex: () -> number,
	findEndIndex: () -> number,
	getItemOffset: (index: number) -> number,
	getItemSize: (index: number) -> number,
	scrollTo: (offset: number, animator: ScrollAnimator?) -> (),
	scrollBy: (offset: number, animator: ScrollAnimator?) -> (),
	scrollToIndex: (index: number, params: ScrollToIndexParams?) -> (),
}

export type Props<T> = {
	data: Source<{ T }>,
	horizontal: boolean?,
	overscan: number,
	itemSize: number,
	startMargin: number?,
	shift: boolean?,
	children: (data: () -> T, index: number) -> Instance,
	onScroll: (offset: number) -> ()?,
	onScrollEnd: () -> ()?,
	ref: (handle: VirtualListHandle) -> ()?,
}

local function VirtualList<T>(props: Props<T>)
	local data = props.data
	local itemSize = props.itemSize
	local overscan = props.overscan
	local horizontal = props.horizontal or false
	local shift = props.shift or false
	local onScroll = props.onScroll
	local onScrollEnd = props.onScrollEnd

	-- Store
	local store = createVirtualStore(#data(), itemSize, overscan, nil)
	local scroller = createScroller(store, horizontal)
	local rerender = source(store.getStateVersion())

	-- Subscriptions
	local unsubscribeStore = store.subscribe(VirtualStoreSubscription.VirtualStateUpdated, function()
		rerender(store.getStateVersion())
	end)

	local unsubscribeOnScroll = store.subscribe(VirtualStoreSubscription.Scroll, function()
		if onScroll then
			onScroll(store.getScrollOffset())
		end
	end)

	local unsubscribeOnScrollEnd = store.subscribe(VirtualStoreSubscription.ScrollEnd, function()
		if onScrollEnd then
			onScrollEnd()
		end
	end)

	local range = source({ store.getRange() })

	effect(function(previous: { number }?)
		rerender()

		local nextRange = { store.getRange() }
		if previous and nextRange[1] == previous[1] and nextRange[2] == previous[2] then
			return previous
		end

		range(nextRange)

		return nextRange
	end)

	local totalSize = derive(function()
		rerender()
		return store.getTotalSize()
	end)

	-- Cleanup
	cleanup(function()
		unsubscribeStore()
		unsubscribeOnScroll()
		unsubscribeOnScrollEnd()
		scroller.destroy()
	end)

	-- Check for data source updates
	effect(function()
		local count = #data()
		if count ~= store.getItemsLength() then
			store.dispatch({
				type = VirtualStoreAction.ItemsChanged,
				length = count,
				shift = shift,
			})
		end
	end)

	-- Check for "jumps" in scrolling.
	effect(function(previousJumpCount)
		rerender()

		local newJumpCount = store.getJumpCount()
		if newJumpCount ~= previousJumpCount then
			scroller.fixScrollJump()
			return newJumpCount
		end

		return previousJumpCount
	end, store.getJumpCount())

	-- Render scroll view
	-- TODO: Custom styles
	return create "ScrollingFrame" {
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.fromScale(1, 1),

		ScrollingDirection = function()
			return if horizontal then Enum.ScrollingDirection.X else Enum.ScrollingDirection.Y
		end,

		AutomaticCanvasSize = function()
			return if horizontal then Enum.AutomaticSize.X else Enum.AutomaticSize.Y
		end,

		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		BorderSizePixel = 0,
		BackgroundTransparency = 1,

		changed("CanvasPosition", scroller.updateScrollPosition),

		changed("AbsoluteSize", function(size)
			store.dispatch({
				type = VirtualStoreAction.ViewportResized,
				size = size,
			})
		end),

		create "Frame" {
			Name = "ContentContainer",

			Size = function()
				return if horizontal then UDim2.new(totalSize(), 0, 1, 0) else UDim2.new(1, 0, 0, totalSize())
			end,

			BackgroundTransparency = 1,

			RangedFor {
				each = data,
				range = range,
				render = function(data: () -> T, index)
					return ListItem {
						index = index,
						offset = store.getItemOffset(index),
						hidden = store.isUnmeasuredItem(index),
						horizontal = horizontal,
						resizer = function(size)
							local value = if horizontal then size.X else size.Y
							if value == 0 then
								return
							end -- Element hasn't performed a layout yet, prevent a dispatch for now.

							store.dispatch({
								type = VirtualStoreAction.ItemResized,
								index = index,
								size = value,
							})
						end,
						children = props.children(data, index),
					}
				end,
			},
		},

		-- Ref
		action(function(ref)
			scroller.setScrollElement(ref :: ScrollingFrame)

			if props.ref then
				props.ref({
					scrollOffset = store.getScrollOffset,
					viewportSize = store.getViewportSize,
					findStartIndex = store.findStartIndex,
					findEndIndex = store.findEndIndex,
					getItemOffset = store.getItemOffset,
					getItemSize = store.getItemSize,
					scrollTo = scroller.scrollTo,
					scrollBy = scroller.scrollBy,
					scrollToIndex = scroller.scrollToIndex,
				})
			end
		end),
	}
end

return VirtualList
