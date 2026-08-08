//
//  LibraryScreens.swift
//  LatitudeCam
//
//  Film Sim, Library, and Edit.
//

import SwiftUI
import UniformTypeIdentifiers

private struct SelectionCellFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - Film Sim

struct FilmSimScreen: View {
    @EnvironmentObject var app: AppState

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ZStack {
            Ink.base.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenHeader(
                        title: "Film Sim",
                        leading: AnyView(ViewfinderReturn { app.go(.viewfinder) })
                    ) {
                        Text(app.selectedFilm.family.uppercased())
                            .font(.mono(9, .semibold))
                            .kerning(1)
                            .foregroundStyle(Accent.amber)
                    }
                    .padding(.bottom, 16)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(FilmPreset.all) { preset in
                            PresetCard(preset: preset, isSelected: preset.id == app.selectedFilm.id) {
                                Haptics.detent()
                                withAnimation(.snappy(duration: 0.2)) { app.selectedFilm = preset }
                            }
                        }
                    }
                    .padding(.bottom, 18)

                    LookPanel(title: app.selectedFilm.name)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
    }
}

private struct PresetCard: View {
    var preset: FilmPreset
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(preset.swatch)
                    .frame(height: 70)
                    .padding(.bottom, 8)

                Text(preset.name)
                    .font(.ui(13, .semibold))
                    .foregroundStyle(Tone.primary)

                Text(preset.blurb)
                    .font(.ui(11))
                    .foregroundStyle(Tone.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Ink.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Accent.amber : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Intensity + grain/halation/vignette — shared by Film Sim and the Edit tab.
struct LookPanel: View {
    @EnvironmentObject var app: AppState
    var title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.ui(13, .semibold))
                    .foregroundStyle(Tone.primary)
                    .padding(.bottom, 12)
            }

            SliderRow(
                label: title == nil ? "\(app.selectedFilm.name) Intensity" : "Intensity",
                value: "\(Int(app.intensity * 100))%",
                position: $app.intensity
            )
            .padding(.bottom, 16)

            HStack(spacing: 8) {
                Chip(title: "Grain", isActive: app.grainOn) { Haptics.toggle(); app.grainOn.toggle() }
                Chip(title: "Halation", isActive: app.halationOn) { Haptics.toggle(); app.halationOn.toggle() }
                Chip(title: "Vignette", isActive: app.vignetteOn) { Haptics.toggle(); app.vignetteOn.toggle() }
            }
        }
        .padding(title == nil ? 0 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if title != nil {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Ink.card)
            }
        }
    }
}

// MARK: - Library

struct LibraryScreen: View {
    @EnvironmentObject var app: AppState
    @AppStorage(Pref.galleryLayout) private var layout = "Organizer"

    var body: some View {
        ZStack {
            Ink.base.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                libraryHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                GalleryHost(gallery: app.gallery, layout: layout)
                    .padding(.horizontal, layout == "Organizer" ? 16 : 0)
            }
        }
    }

    private var libraryHeader: some View {
        ScreenHeader(
            title: "Library",
            leading: AnyView(ViewfinderReturn { app.go(.viewfinder) })
        ) {
            Text("\(app.gallery.photos.count) FRAMES")
                .font(.mono(11, .semibold))
                .kerning(1)
                .foregroundStyle(Tone.secondary)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Tone.hairline, lineWidth: 0.5) }
                }
        }
    }
}

/// The full roll, one frame at a time, with somewhere to go from whichever one
/// is on screen. Looking and editing are different intentions and this is what
/// separates them; paging is what makes it a viewer rather than a single photo
/// wearing a close button.
struct PhotoViewer: View {
    @ObservedObject var gallery: PhotoGallery
    var photos: [PhotoGallery.Photo]
    var startingAt: String
    var onEdit: (PhotoGallery.Photo) -> Void
    var onDelete: (PhotoGallery.Photo) -> Void
    var onClose: () -> Void

    @State private var current: String

    init(
        gallery: PhotoGallery, photos: [PhotoGallery.Photo], startingAt: String,
        onEdit: @escaping (PhotoGallery.Photo) -> Void,
        onDelete: @escaping (PhotoGallery.Photo) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.gallery = gallery
        self.photos = photos
        self.startingAt = startingAt
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onClose = onClose
        self._current = State(initialValue: startingAt)
    }

    @State private var showMetadata = false

    private var index: Int { photos.firstIndex { $0.id == current } ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ScreenReturn(title: "Close", action: onClose)
                Spacer()
                if photos.count > 1 {
                    Text("\(index + 1) OF \(photos.count)")
                        .font(.mono(11, .semibold))
                        .kerning(1)
                        .foregroundStyle(Tone.secondary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Tone.hairline, lineWidth: 0.5) }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // One paged scroll rather than a manual swipe gesture: paging,
            // momentum and the settle onto a whole frame all come from the
            // system for free, and each page keeps its own pinch state
            // independently. Bounded to the space between the header and the
            // button bar rather than the whole screen — the image no longer
            // sits under floating controls, it sits in its own region.
            TabView(selection: $current) {
                ForEach(photos) { photo in
                    ZoomableImage(gallery: gallery, photo: photo)
                        .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxHeight: .infinity)

            // A sibling of the TabView, not a child of it. A drag gesture placed
            // on the image itself loses to the TabView's own paging pan
            // recognizer almost every time — that recognizer is a UIScrollView
            // under the hood and isn't part of SwiftUI's gesture arena, so
            // .simultaneousGesture there never reliably won. Down here it has
            // no paging gesture to compete with, so it works. A tap is included
            // too, since a swipe on a handle this small is easy to miss.
            VStack(spacing: 4) {
                Capsule()
                    .fill(Tone.quaternary.opacity(0.4))
                    .frame(width: 32, height: 3)
                Text("SWIPE UP FOR DETAILS")
                    .font(.mono(7.5, .medium))
                    .kerning(1)
                    .foregroundStyle(Tone.quaternary.opacity(0.6))
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.tap()
                showMetadata = true
            }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onEnded { value in
                        if value.translation.height < -15 {
                            Haptics.tap()
                            showMetadata = true
                        }
                    }
            )

            // A real toolbar below the picture, not two pills floating over it.
            // The photo used to sit directly under Delete and Edit, which is
            // also where a thumb rests to swipe between pages — the two kept
            // competing for the same touches.
            HStack(spacing: 10) {
                GalleryAction(title: "Delete", role: .destructive) {
                    Haptics.toggle()
                    if let photo = current(in: photos) { onDelete(photo) }
                }

                GalleryAction(title: "Edit", role: .primary) {
                    Haptics.tap()
                    if let photo = current(in: photos) { onEdit(photo) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Ink.base.ignoresSafeArea())
        .overlay {
            if showMetadata, let photo = current(in: photos) {
                BottomSheet(onDismiss: { showMetadata = false }) {
                    metadataContent(photo)
                }
                .zIndex(6)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: showMetadata)
    }

    private func current(in photos: [PhotoGallery.Photo]) -> PhotoGallery.Photo? {
        photos.first { $0.id == current }
    }

    private func metadataContent(_ photo: PhotoGallery.Photo) -> some View {
        let preset = FilmPreset.all.first { $0.id == photo.filmID }
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return f
        }()

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Circle().fill(preset?.swatch ?? FilmSwatch.amber).frame(width: 10, height: 10)
                Text(preset?.name ?? "—")
                    .font(.ui(16, .semibold))
                    .foregroundStyle(Tone.primary)
            }

            VStack(spacing: 0) {
                metadataRow("Family", preset?.family ?? "—")
                metadataRow("ISO", "\(photo.iso)")
                metadataRow("Shutter", "1/\(photo.shutterDenominator)")
                metadataRow("Taken", formatter.string(from: photo.timestamp), isLast: true)
            }
        }
    }

    private func metadataRow(_ label: String, _ value: String, isLast: Bool = false) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.mono(10, .semibold))
                .kerning(0.6)
                .foregroundStyle(Tone.quaternary)
            Spacer()
            Text(value)
                .font(.ui(14, .medium))
                .foregroundStyle(Tone.primary)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Tone.separator).frame(height: 0.5)
            }
        }
    }
}

/// One page of the viewer: a photo that pinches to zoom and drags while zoomed,
/// and snaps back the moment it is released at 1×.
private struct ZoomableImage: View {
    @ObservedObject var gallery: PhotoGallery
    var photo: PhotoGallery.Photo

    // Starts on the grid thumbnail, already in hand, and is replaced the moment
    // the full-resolution roll copy arrives — the same fast-then-sharp pattern
    // opportunistic delivery uses for the grid itself, so opening a photo never
    // shows a blank frame while the real image decodes.
    @State private var image: UIImage
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .contentShape(Rectangle())
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(max(lastScale * value, 1), 5)
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale <= 1.01 {
                                // Below 1× the image is stuck to a size smaller
                                // than its frame; there is nothing to pan, and
                                // TabView needs the swipe back for paging.
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    scale = 1; lastScale = 1
                                    offset = .zero; lastOffset = .zero
                                }
                            }
                            Haptics.detent()
                        }
                )
                .simultaneousGesture(
                    // Only competes with paging once zoomed — at 1× the page
                    // TabView owns horizontal drags outright, which is what lets
                    // swiping between photos keep working when not zoomed in.
                    scale > 1.01 ?
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in lastOffset = offset }
                    : nil
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        if scale > 1.01 {
                            scale = 1; lastScale = 1
                            offset = .zero; lastOffset = .zero
                        } else {
                            scale = 2.5; lastScale = 2.5
                        }
                    }
                    Haptics.detent()
                }
        }
        .onAppear {
            gallery.loadFullImage(for: photo) { full in
                if let full { image = full }
            }
        }
    }

    init(gallery: PhotoGallery, photo: PhotoGallery.Photo) {
        self.gallery = gallery
        self.photo = photo
        self._image = State(initialValue: photo.thumb)
    }
}

/// Owns the filter state, the gallery subscription, and the family/frame
/// bookkeeping every layout needs — so the surrounding screen does not rebuild
/// when photos load in off the disk queue, and the four layouts do not each
/// reimplement "what family is this photo" and "open the viewer."
private struct GalleryHost: View {
    @ObservedObject var gallery: PhotoGallery
    @EnvironmentObject var app: AppState
    var layout: String
    @State private var filter = "All"
    @State private var viewing: PhotoGallery.Photo?
    @State private var selectionMode = false
    @State private var selectedIDs: Set<String> = []
    @State private var showBulkDeleteConfirmation = false
    @State private var isTrashTargeted = false
    @State private var isDeletingSelection = false
    @State private var deletionWatchdog: DispatchWorkItem?
    @State private var selectionCellFrames: [String: CGRect] = [:]
    @State private var swipedPhotoIDs: Set<String> = []
    @State private var swipeSelects: Bool?
    @State private var deletionFailure: String?
    @State private var suppressNextOpenID: String?

    /// 2, 3 or 4 across. A pinch changes the count rather than the image scale —
    /// scaling the images themselves inside a fixed grid would just crop them,
    /// which is not what "zoom" means to someone looking at a contact sheet.
    @State private var columnCount = 3
    @State private var pinchStart = 3

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: columnCount)
    }

    /// Families, not stocks. Twelve chips in a fixed HStack ran off the right of
    /// the screen with no way to reach the ones past the edge — which is what
    /// "the gallery is out of frame" was. Five fit, and a family is the useful
    /// question anyway: you look for the black and white ones, not for Ash.
    private static var categories: [String] { ["All"] + AppState.filmFamilies }

    private func family(of photo: PhotoGallery.Photo) -> String {
        FilmPreset.all.first { $0.id == photo.filmID }?.family ?? "Signature"
    }

    private var filtered: [PhotoGallery.Photo] {
        guard filter != "All" else { return gallery.photos }
        return gallery.photos.filter { family(of: $0) == filter }
    }

    private func count(_ category: String) -> Int {
        category == "All" ? gallery.photos.count
                          : gallery.photos.filter { family(of: $0) == category }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Scrolls as well as fits, so a sixth family later cannot put a chip
            // out of reach again.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.categories, id: \.self) { name in
                        FilterChip(title: "\(name) \(count(name))", isActive: filter == name) {
                            Haptics.detent()
                            withAnimation(.snappy(duration: 0.2)) { filter = name }
                        }
                        .opacity(count(name) == 0 && name != "All" ? 0.4 : 1)
                    }
                }
                .padding(.horizontal, 1)
            }
            .padding(.bottom, 10)

            if !selectionMode && !filtered.isEmpty {
                Label("Press and hold a photo to select", systemImage: "hand.tap.fill")
                    .font(.ui(12, .medium))
                    .foregroundStyle(Tone.tertiary)
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .background(Color.white.opacity(0.045), in: Capsule())
                    .padding(.bottom, 18)
            }

            if selectionMode {
                selectionToolbar
                    .padding(.bottom, 18)
            }

            if filtered.isEmpty {
                emptyState
            } else if selectionMode {
                selectionGrid
            } else if layout == "Organizer" {
                ScrollView { organizerGrid }
            } else {
                // The three other layouts had no scroll container at all — each
                // rendered at whatever size its content happened to need and then
                // stopped, which is what "all over the place" was: nothing below
                // the fold could be reached, and short content left dead space.
                ScrollView {
                    switch layout {
                    case "Contact Roll": ContactRollLayout(photos: filtered, open: open, beginSelection: beginSelection, swatch: swatch)
                    case "Archive":      ArchiveLayout(gallery: gallery, filter: $filter, open: open, beginSelection: beginSelection, family: family, swatch: swatch)
                    case "Darkroom":     DarkroomLineLayout(photos: filtered, open: open, beginSelection: beginSelection, swatch: swatch)
                    default:             StoryboardLayout(photos: filtered, open: open, beginSelection: beginSelection, swatch: swatch)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            if selectionMode { selectionDelete }
        }
        // fullScreenCover, not an inline overlay. An overlay is sized to whatever
        // frame its host view actually occupies — for a layout that hugs its
        // content instead of filling the screen, that host frame could be far
        // smaller than the device, and the "opened" photo was rendered clipped to
        // it: too small, and with its own Close button potentially laid outside
        // the region that was actually receiving taps, which is what made the
        // Storyboard layout's back button look broken. fullScreenCover is sized
        // by the system to the full device bounds regardless of the presenting
        // view's own size, so this cannot happen in any layout.
        .fullScreenCover(item: $viewing) { photo in
            PhotoViewer(
                gallery: gallery,
                photos: filtered,
                startingAt: photo.id,
                onEdit: { chosen in
                    app.editingPhoto = chosen
                    viewing = nil
                    app.go(.edit)
                },
                onDelete: { chosen in gallery.deletePhoto(chosen.id) },
                onClose: { viewing = nil }
            )
        }
        .alert("Delete selected frames?", isPresented: $showBulkDeleteConfirmation) {
            Button("Delete \(selectedIDs.count)", role: .destructive) {
                deleteSelectedFrames()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the selected frames from Latitude and the Latitude album in Apple Photos.")
        }
        .alert("Could not delete frames", isPresented: Binding(
            get: { deletionFailure != nil },
            set: { if !$0 { deletionFailure = nil } }
        )) {
            Button("OK", role: .cancel) { deletionFailure = nil }
        } message: {
            Text(deletionFailure ?? "Photos could not delete the selected frames.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(gallery.photos.isEmpty ? "No shots yet" : "Nothing in \(filter)")
                .font(.ui(15, .semibold))
                .foregroundStyle(Tone.secondary)
            Text(gallery.photos.isEmpty
                 ? "Tap the shutter in the viewfinder to start a roll."
                 : "No frames on this shelf yet.")
                .font(.ui(12))
                .foregroundStyle(Tone.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var selectionToolbar: some View {
        HStack(spacing: 12) {
            if selectionMode {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SELECTION")
                        .font(.mono(8, .semibold))
                        .kerning(1)
                        .foregroundStyle(Tone.quaternary)
                    Text("\(selectedIDs.count) FRAME\(selectedIDs.count == 1 ? "" : "S")")
                        .font(.mono(11, .bold))
                        .kerning(0.7)
                        .foregroundStyle(selectedIDs.isEmpty ? Tone.quaternary : Accent.amber)
                }

                Spacer()

                Button(allVisibleSelected ? "Clear" : "All") {
                    Haptics.detent()
                    let visibleIDs = Set(filtered.map(\.id))
                    if allVisibleSelected {
                        selectedIDs.subtract(visibleIDs)
                    } else {
                        selectedIDs.formUnion(visibleIDs)
                    }
                }
                .buttonStyle(.plain)
                .font(.ui(13, .semibold))
                .foregroundStyle(Tone.primary)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Color.white.opacity(0.06), in: Capsule())

                Button("Done") {
                    Haptics.tap()
                    selectedIDs.removeAll()
                    selectionMode = false
                }
                .buttonStyle(.plain)
                .font(.ui(13, .semibold))
                .foregroundStyle(Tone.secondary)
                .padding(.horizontal, 6)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Tone.hairline, lineWidth: 0.5)
        }
    }

    private var selectionGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(filtered) { photo in
                    Button { toggleSelection(for: photo) } label: {
                        gridCell(photo)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        selectedIDs.contains(photo.id) ? Accent.amber : .clear,
                                        lineWidth: 3
                                    )
                            }
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: selectedIDs.contains(photo.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 23, weight: .semibold))
                                    .foregroundStyle(selectedIDs.contains(photo.id) ? Accent.amber : .white.opacity(0.84))
                                    .shadow(color: .black.opacity(0.65), radius: 3)
                                    .padding(7)
                            }
                    }
                    .buttonStyle(.plain)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: SelectionCellFramesKey.self,
                                value: [photo.id: proxy.frame(in: .named("selection-grid"))]
                            )
                        }
                    }
                    .onDrag {
                        // Native long-press drag carries the current batch into Delete.
                        selectedIDs.insert(photo.id)
                        return NSItemProvider(object: photo.id as NSString)
                    }
                }
            }
            .padding(.bottom, 92)
            .contentShape(Rectangle())
            // A moving finger selects across cells. A stationary long press is
            // left to .onDrag above, preserving drag-and-drop to the Delete bin.
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        // The first changed value can already be over the next
                        // cell, so include the touch-down cell explicitly.
                        selectPhotoAlongSwipe(at: value.startLocation)
                        selectPhotoAlongSwipe(at: value.location)
                    }
                    .onEnded { _ in
                        swipedPhotoIDs.removeAll()
                        swipeSelects = nil
                    },
                including: .all
            )
        }
        .coordinateSpace(name: "selection-grid")
        .onPreferenceChange(SelectionCellFramesKey.self) { selectionCellFrames = $0 }
    }

    private var allVisibleSelected: Bool {
        let visibleIDs = Set(filtered.map(\.id))
        return !visibleIDs.isEmpty && visibleIDs.isSubset(of: selectedIDs)
    }

    private var selectionDelete: some View {
        Button {
            guard !selectedIDs.isEmpty && !isDeletingSelection else { return }
            showBulkDeleteConfirmation = true
        } label: {
            HStack(spacing: 10) {
                ZStack(alignment: .top) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 25, weight: .bold))
                    if isDeletingSelection {
                        // Keep the hinge on the icon rather than floating a lid
                        // above the enlarged button.
                        Capsule()
                            .fill(.white)
                            .frame(width: 24, height: 4)
                            .rotationEffect(.degrees(-32), anchor: .trailing)
                            .offset(x: -2, y: -8)
                        DeleteFilmDrop()
                    }
                }
                .frame(width: 44, height: 44)
                if !isDeletingSelection {
                    Text(selectedIDs.isEmpty ? "DELETE" : "DELETE \(selectedIDs.count)")
                    .font(.mono(10, .bold))
                    .kerning(0.7)
                }
            }
            .foregroundStyle(selectedIDs.isEmpty ? Tone.quaternary : .white)
            .padding(.horizontal, 24)
            .frame(width: isDeletingSelection ? 92 : 166, height: 64)
            .background(isDeletingSelection || isTrashTargeted ? Color.red.opacity(0.9) : Color(hex: 0x2A1718),
                        in: Capsule())
            .overlay { Capsule().strokeBorder(Color.red.opacity(0.55), lineWidth: 0.8) }
            .shadow(color: .black.opacity(0.45), radius: isDeletingSelection ? 18 : 10, y: 5)
            // The existing bottom bin grows in place, anchored to the screen edge.
            .scaleEffect(isDeletingSelection ? 1.28 : 1, anchor: .bottom)
            .animation(.spring(response: 0.4, dampingFraction: 0.82), value: isDeletingSelection)
        }
        .buttonStyle(.plain)
        .onDrop(of: [UTType.text.identifier, UTType.plainText.identifier], isTargeted: $isTrashTargeted) { providers in
            guard let provider = providers.first else { return false }
            if selectedIDs.isEmpty {
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let id = object as? String else { return }
                    DispatchQueue.main.async {
                        selectedIDs.insert(id)
                        showBulkDeleteConfirmation = true
                    }
                }
            } else {
                showBulkDeleteConfirmation = true
            }
            return true
        }
        .padding(.bottom, 18)
    }

    private func deleteSelectedFrames() {
        guard !selectedIDs.isEmpty, !isDeletingSelection else { return }
        Haptics.destructive()
        isDeletingSelection = true
        let ids = selectedIDs

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            let watchdog = DispatchWorkItem {
                guard isDeletingSelection else { return }
                isDeletingSelection = false
                deletionFailure = "Apple Photos did not finish the deletion. No frames were removed; please try again."
            }
            deletionWatchdog?.cancel()
            deletionWatchdog = watchdog
            DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: watchdog)

            gallery.deletePhotos(ids) { success, problem in
                DispatchQueue.main.async {
                    deletionWatchdog?.cancel()
                    deletionWatchdog = nil
                    isDeletingSelection = false
                    if success {
                        selectedIDs.removeAll()
                        selectionMode = false
                    } else {
                        deletionFailure = problem
                    }
                }
            }
        }

    }

    /// Brief film strips fall into the existing bin once its lid opens.
    private struct DeleteFilmDrop: View {
        @State private var hasShredded = false

        var body: some View {
            ZStack {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Accent.amber.opacity(0.95))
                        .frame(width: 7, height: 10)
                        .rotationEffect(.degrees(hasShredded ? Double(index * 20 - 40) : 0))
                        .offset(
                            x: hasShredded ? CGFloat(index - 2) * 7 : 0,
                            y: hasShredded ? 18 : -18
                        )
                        .opacity(hasShredded ? 0 : 1)
                        .animation(.easeIn(duration: 0.46).delay(Double(index) * 0.06), value: hasShredded)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { hasShredded = true }
            }
        }
    }

    private func toggleSelection(for photo: PhotoGallery.Photo) {
        Haptics.detent()
        if selectedIDs.contains(photo.id) {
            selectedIDs.remove(photo.id)
        } else {
            selectedIDs.insert(photo.id)
        }
    }

    /// Uses the rendered cell bounds, not inferred grid math, so a swipe stays
    /// accurate when the grid spacing, columns, or scroll offset changes.
    private func selectPhotoAlongSwipe(at point: CGPoint) {
        guard let id = selectionCellFrames.first(where: { $0.value.contains(point) })?.key,
              let photo = filtered.first(where: { $0.id == id })
        else { return }
        guard !swipedPhotoIDs.contains(photo.id) else { return }

        if swipeSelects == nil {
            swipeSelects = !selectedIDs.contains(photo.id)
        }
        guard let swipeSelects else { return }

        swipedPhotoIDs.insert(photo.id)
        if swipeSelects {
            if selectedIDs.insert(photo.id).inserted { Haptics.detent() }
        } else if selectedIDs.remove(photo.id) != nil {
            Haptics.detent()
        }
    }

    private func beginSelection(_ photo: PhotoGallery.Photo) {
        Haptics.toggle()
        selectedIDs.insert(photo.id)
        selectionMode = true
        suppressNextOpenID = photo.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if suppressNextOpenID == photo.id { suppressNextOpenID = nil }
        }
    }

    /// Opens the viewer rather than the editor — tapping a photo used to drop
    /// straight into edit controls, which answered a question nobody asked.
    private func open(_ photo: PhotoGallery.Photo) {
        if suppressNextOpenID == photo.id {
            suppressNextOpenID = nil
            return
        }
        if selectionMode {
            toggleSelection(for: photo)
            return
        }
        Haptics.tap()
        withAnimation(.easeOut(duration: 0.18)) { viewing = photo }
    }

    private var organizerGrid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(filtered) { photo in
                Button { open(photo) } label: {
                    gridCell(photo)
                }
                .buttonStyle(.plain)
                .highPriorityGesture(LongPressGesture(minimumDuration: 0.3, maximumDistance: 20).onEnded { _ in beginSelection(photo) })
                .contextMenu { contextMenu(photo) }
            }
        }
        // Column count, not image scale: scaling the photos inside a fixed
        // grid would only crop them, which is not what "zoom" means to
        // someone looking at a contact sheet. Snapped to a whole column so
        // the pinch has a definite place to land rather than settling on a
        // fractional width.
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: columnCount)
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    let proposed = Double(pinchStart) / value
                    columnCount = min(5, max(2, Int(proposed.rounded())))
                }
                .onEnded { _ in
                    pinchStart = columnCount
                    Haptics.detent()
                }
        )
    }

    @ViewBuilder
    private func contextMenu(_ photo: PhotoGallery.Photo) -> some View {
        Button("Edit") {
            Haptics.tap()
            app.editingPhoto = photo
            app.go(.edit)
        }
        Button("Delete", role: .destructive) {
            Haptics.toggle()
            gallery.deletePhoto(photo.id)
        }
    }

    /// Colour.clear sets the cell size and the photo fills it from an overlay.
    /// Sizing the Image directly let a 1080px frame lay out far bigger than its
    /// cell — clipped() hides that but hit testing still used the full bounds, so
    /// the top row swallowed taps meant for the back button.
    private func gridCell(_ photo: PhotoGallery.Photo) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(uiImage: photo.thumb)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .bottomLeading) {
                Circle()
                    .fill(swatch(for: photo.filmID))
                    .frame(width: 8, height: 8)
                    .overlay {
                        Circle().strokeBorder(
                            photo.filmID == "mono" ? Color.white.opacity(0.3) : .clear,
                            lineWidth: 1
                        )
                    }
                    .padding(5)
            }
    }

    private func swatch(for filmID: String) -> Color {
        FilmPreset.all.first { $0.id == filmID }?.swatch ?? FilmSwatch.amber
    }
}

// MARK: - Contact roll layout
//
// The whole roll as one continuous filmstrip, sprockets down both edges. The
// same visual object the film barrel on the camera screen already is, so
// reaching the library does not mean learning a second vocabulary for what
// film looks like.

private struct ContactRollLayout: View {
    var photos: [PhotoGallery.Photo]
    var open: (PhotoGallery.Photo) -> Void
    var beginSelection: (PhotoGallery.Photo) -> Void
    var swatch: (String) -> Color

    var body: some View {
        VStack(spacing: 0) {
            sprocketRow
            LazyVStack(spacing: 2) {
                ForEach(photos) { photo in
                    Button { open(photo) } label: {
                        ZStack(alignment: .bottomLeading) {
                            Image(uiImage: photo.thumb)
                                .resizable()
                                .aspectRatio(3/2, contentMode: .fill)
                                .frame(height: 92)
                                .clipped()

                            HStack(spacing: 5) {
                                Circle().fill(swatch(photo.filmID)).frame(width: 6, height: 6)
                                Text(stamp(photo))
                                    .font(.mono(7, .semibold))
                                    .kerning(0.4)
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            .padding(8)
                            .background {
                                LinearGradient(colors: [.black.opacity(0.55), .clear],
                                               startPoint: .bottom, endPoint: .top)
                                    .frame(height: 36)
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .highPriorityGesture(LongPressGesture(minimumDuration: 0.3, maximumDistance: 20).onEnded { _ in beginSelection(photo) })
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color(hex: 0x0A0908)).frame(height: 2)
                    }
                }
            }
            sprocketRow
        }
        .background(Color(hex: 0x141210))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var sprocketRow: some View {
        HStack(spacing: 9) {
            ForEach(0..<11, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5).fill(.white.opacity(0.16)).frame(width: 8, height: 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(hex: 0x0A0908))
    }

    private func stamp(_ photo: PhotoGallery.Photo) -> String {
        let name = FilmPreset.all.first { $0.id == photo.filmID }?.shortName.uppercased() ?? "—"
        return "\(name) · ISO \(photo.iso) · 1/\(photo.shutterDenominator)"
    }
}

// MARK: - Darkroom line layout
//
// Prints clipped to a washing line, freshly developed. Several lines stacked
// vertically, each scrolling horizontally, rather than one line trying to hold
// an entire roll — a real line runs out of room, and so does a phone screen.

private struct DarkroomLineLayout: View {
    var photos: [PhotoGallery.Photo]
    var open: (PhotoGallery.Photo) -> Void
    var beginSelection: (PhotoGallery.Photo) -> Void
    var swatch: (String) -> Color

    private static let perLine = 5

    private var lines: [[PhotoGallery.Photo]] {
        stride(from: 0, to: photos.count, by: Self.perLine).map {
            Array(photos[$0..<min($0 + Self.perLine, photos.count)])
        }
    }

    var body: some View {
        LazyVStack(spacing: 30) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                ZStack(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.22)).frame(height: 1).padding(.top, 8)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 18) {
                            ForEach(line) { photo in
                                clippedPrint(photo)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private func clippedPrint(_ photo: PhotoGallery.Photo) -> some View {
        // A stable, deterministic tilt from the photo's own id rather than
        // Double.random — a fresh random value on every body re-evaluation
        // would make the print visibly jitter each time SwiftUI redraws it.
        let tilt = Double(abs(photo.id.hashValue) % 9) - 4

        return Button { open(photo) } label: {
            VStack(spacing: 0) {
                Capsule().fill(Color(hex: 0xC9A227)).frame(width: 12, height: 4).offset(y: 2)
                ZStack(alignment: .bottomLeading) {
                    Image(uiImage: photo.thumb)
                        .resizable()
                        .aspectRatio(3/2, contentMode: .fill)
                        .frame(width: 108, height: 72)
                        .clipped()
                    Circle().fill(swatch(photo.filmID)).frame(width: 7, height: 7).padding(5)
                }
                .background(.white)
                .padding(4)
                .background(.white)
                .shadow(color: .black.opacity(0.4), radius: 6, y: 4)
            }
            .rotationEffect(.degrees(tilt))
        }
        .buttonStyle(.plain)
        .highPriorityGesture(LongPressGesture(minimumDuration: 0.3, maximumDistance: 20).onEnded { _ in beginSelection(photo) })
    }
}

// MARK: - Archive layout
//
// A filing cabinet, one drawer per family. The family grouping already exists
// as the two-tier film selector on the camera screen; this is the same idea
// turned into furniture rather than a second, unrelated organising principle.

private struct ArchiveLayout: View {
    @ObservedObject var gallery: PhotoGallery
    @Binding var filter: String
    var open: (PhotoGallery.Photo) -> Void
    var beginSelection: (PhotoGallery.Photo) -> Void
    var family: (PhotoGallery.Photo) -> String
    var swatch: (String) -> Color

    @State private var expanded: Set<String> = []

    private var families: [String] {
        var seen: [String] = []
        for photo in gallery.photos {
            let f = family(photo)
            if !seen.contains(f) { seen.append(f) }
        }
        return seen
    }

    private func photos(in fam: String) -> [PhotoGallery.Photo] {
        gallery.photos.filter { family($0) == fam }
    }

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(families, id: \.self) { fam in
                drawer(fam)
            }
        }
    }

    private func drawer(_ fam: String) -> some View {
        let open = expanded.contains(fam)
        let count = photos(in: fam).count

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.detent()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    if open { expanded.remove(fam) } else { expanded.insert(fam) }
                }
            } label: {
                HStack(spacing: 10) {
                    Capsule().fill(Accent.amber).frame(width: 22, height: 3)
                    Text(fam.uppercased())
                        .font(.mono(11, .semibold))
                        .kerning(1)
                        .foregroundStyle(Tone.primary)
                    Spacer()
                    Text("\(count)")
                        .font(.mono(10, .medium))
                        .foregroundStyle(Tone.quaternary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Tone.quaternary)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(photos(in: fam)) { photo in
                            Button { self.open(photo) } label: {
                                Image(uiImage: photo.thumb)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 84, height: 84)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .highPriorityGesture(LongPressGesture(minimumDuration: 0.3, maximumDistance: 20).onEnded { _ in beginSelection(photo) })
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    Haptics.toggle()
                                    gallery.deletePhoto(photo.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Storyboard layout
//
// Unequal panels — the newest shot always gets the dominant one. Reads as a
// sequence of moments rather than a uniform archive, and needs no metadata to
// make its point: recency alone decides the size.

private struct StoryboardLayout: View {
    var photos: [PhotoGallery.Photo]
    var open: (PhotoGallery.Photo) -> Void
    var beginSelection: (PhotoGallery.Photo) -> Void
    var swatch: (String) -> Color

    var body: some View {
        LazyVStack(spacing: 6) {
            ForEach(Array(chunked.enumerated()), id: \.offset) { _, group in
                row(group)
            }
        }
    }

    /// Groups of four: one dominant frame, three supporting. `photos` is
    /// already newest-first, so the dominant slot in every group is the most
    /// recent frame in it.
    private var chunked: [[PhotoGallery.Photo]] {
        stride(from: 0, to: photos.count, by: 4).map {
            Array(photos[$0..<min($0 + 4, photos.count)])
        }
    }

    @ViewBuilder
    private func row(_ group: [PhotoGallery.Photo]) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if let lead = group.first {
                panel(lead, height: 176)
                    .frame(maxWidth: .infinity)
            }
            if group.count > 1 {
                VStack(spacing: 6) {
                    ForEach(group.dropFirst()) { photo in
                        panel(photo, height: 56)
                    }
                }
                .frame(width: 92)
            }
        }
    }

    private func panel(_ photo: PhotoGallery.Photo, height: CGFloat) -> some View {
        Button { open(photo) } label: {
            ZStack(alignment: .bottomLeading) {
                Image(uiImage: photo.thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(height: height)
                    .clipped()
                Circle()
                    .fill(swatch(photo.filmID))
                    .frame(width: 7, height: 7)
                    .padding(6)
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .highPriorityGesture(LongPressGesture(minimumDuration: 0.3, maximumDistance: 20).onEnded { _ in beginSelection(photo) })
    }
}

// MARK: - Edit

struct EditScreen: View {
    @EnvironmentObject var app: AppState
    @StateObject private var editor = PhotoEditor()
    @State private var tab = "Light"

    /// Nil while editing. Set for the duration of a write back to Photos, which
    /// is not instant — Photos renders the frame and swaps it in.
    @State private var saving: DevelopingOverlay.Phase?
    @State private var savingImage: UIImage?
    /// Whether this frame already carries one of our edits, which is what makes
    /// "Revert" worth offering. Asked of Photos rather than remembered, because
    /// it can also be edited or reverted in Photos itself.
    @State private var hasEdit = false

    var body: some View {
        ZStack {
            Ink.base.ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: 0) {
                    header

                    // The picture takes whatever the controls do not. Capping the
                    // preview instead left it small on every screen size; bounding
                    // the controls means the photograph grows with the phone,
                    // which is the right way round for a thing you are looking at.
                    preview
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    tabBar
                        .padding(.vertical, 12)

                    // Under a third of the screen, whatever the group holds. Five
                    // barrels do not fit that and are not meant to — the scroll is
                    // the mechanism, not a fallback.
                    ScrollViewReader { proxy in
                        ScrollView {
                            panel
                                .padding(.horizontal, 18)
                                .padding(.bottom, 24)
                        }
                        // The system's own indicator is a two-point hairline that
                        // fades: too thin to notice and impossible to grab. This
                        // one is drawn, stays put, and can be dragged.
                        .scrollIndicators(.hidden)
                        .overlay(alignment: .trailing) {
                            ScrollRail(rows: barrelControls.count) { row in
                                withAnimation(.easeOut(duration: 0.18)) {
                                    proxy.scrollTo(row, anchor: .top)
                                }
                            }
                        }
                    }
                    .frame(height: geo.size.height * 0.30)
                }
            }
        }
        .onAppear {
            // Starts from the grid thumbnail already in memory, then upgrades to
            // the full-resolution roll copy — the editor used to require every
            // photo in the album decoded at 1280pt up front just to open one.
            editor.load(app.editingPhoto)
            if let photo = app.editingPhoto {
                app.gallery.loadFullImage(for: photo) { full in
                    if let full { editor.load(app.editingPhoto, image: full) }
                }
                app.gallery.hasEdit(photo) { hasEdit = $0 }
            }
        }
        .overlay {
            if let saving {
                DevelopingOverlay(phase: saving, image: savingImage)
                    .zIndex(9)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            ScreenReturn(title: "Library") { app.go(.library) }
            Spacer()
            GalleryAction(title: "Reset", role: .secondary, compact: true) {
                Haptics.toggle()
                editor.reset()
            }
            if hasEdit {
                GalleryAction(title: "Revert", role: .secondary, compact: true) {
                    Haptics.toggle()
                    revert()
                }
            }
            GalleryAction(title: "Cancel", role: .secondary, compact: true) {
                Haptics.tap()
                editor.reset()
                app.go(.library)
            }
            PrimaryAction(title: "Save", enabled: editor.canSave) { save() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// Edits the frame itself rather than filing a second one beside it.
    ///
    /// It used to call addPhoto, so every save grew the roll by one and Apple
    /// Photos never heard about the change. The asset is edited in place now,
    /// through the same adjustment-data mechanism Photos' own editor uses: the
    /// change appears in Photos, and the original is kept by the system, which
    /// is what makes Revert possible at all — including after quitting the app.
    private func save() {
        guard let edited = editor.flattened(), let source = app.editingPhoto else { return }

        savingImage = edited
        withAnimation(.easeInOut(duration: 0.24)) { saving = .developing }
        Haptics.tap()

        app.gallery.applyEdit(to: source, image: edited, filmID: editor.filmID) { result in
            switch result {
            case .saved:
                Haptics.shutter()
                withAnimation(.easeInOut(duration: 0.24)) { saving = .done("Saved to this photo") }
                dismissAfterSave()
            case .reverted:
                withAnimation(.easeInOut(duration: 0.24)) { saving = .done("Reverted") }
                dismissAfterSave()
            case .failed(let reason):
                Haptics.blocked()
                withAnimation(.easeInOut(duration: 0.24)) { saving = .failed(reason) }
                dismissAfterSave(delay: 2.4, thenLeave: false)
            }
        }
    }

    /// Puts the frame back the way it was taken. Photos still holds the
    /// original, so this discards the edit rather than reconstructing anything.
    private func revert() {
        guard let source = app.editingPhoto else { return }

        savingImage = editor.preview
        withAnimation(.easeInOut(duration: 0.24)) { saving = .developing }

        app.gallery.revertEdit(source) { result in
            switch result {
            case .reverted, .saved:
                Haptics.shutter()
                hasEdit = false
                editor.reset()
                withAnimation(.easeInOut(duration: 0.24)) { saving = .done("Back to the original") }
                dismissAfterSave()
            case .failed(let reason):
                Haptics.blocked()
                withAnimation(.easeInOut(duration: 0.24)) { saving = .failed(reason) }
                dismissAfterSave(delay: 2.4, thenLeave: false)
            }
        }
    }

    /// Holds the finished state long enough to be read, then gets out of the
    /// way. A confirmation that vanishes on the same frame it appears is the
    /// same as no confirmation.
    private func dismissAfterSave(delay: Double = 0.9, thenLeave: Bool = true) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            withAnimation(.easeInOut(duration: 0.24)) { saving = nil }
            savingImage = nil
            if thenLeave { app.go(.library) }
        }
    }

    // MARK: Preview

    private var preview: some View {
        ZStack {
            Ink.card
            if let image = editor.preview {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Text(app.editingPhoto == nil ? "NO PHOTO SELECTED" : "LOADING…")
                    .font(.mono(11, .medium))
                    .foregroundStyle(Color.white.opacity(0.25))
            }
        }
    }

    /// The controls each barrel tab holds. One list, read by the panel that draws
    /// them and by the rail that has to know how far the panel goes.
    private var barrelControls: [(String, Binding<Double>, Int, (Double) -> String)] {
        switch tab {
        case "Light":
            return [
                ("Exposure", $editor.exposure, 25, { String(format: "%+.1f", ($0 - 0.5) * 4) }),
                ("Contrast", $editor.contrast, 21, { String(format: "%+.0f", ($0 - 0.5) * 200) }),
                ("Highlights", $editor.highlights, 21, { String(format: "%+.0f", (0.5 - $0) * 200) }),
                ("Shadows", $editor.shadows, 21, { String(format: "%+.0f", ($0 - 0.5) * 200) }),
                ("Blacks", $editor.blackPoint, 21, { String(format: "%+.0f", ($0 - 0.5) * 200) })
            ]
        case "Color":
            return [
                ("Temp", $editor.temperature, 21, { "\(Int(((3000 + $0 * 6000) / 100).rounded() * 100 / 100))" }),
                ("Tint", $editor.tint, 21, { String(format: "%+.0f", ($0 - 0.5) * 150) }),
                ("Saturation", $editor.saturation, 21, { String(format: "%.2f", $0 * 2) }),
                ("Vibrance", $editor.vibrance, 21, { String(format: "%+.0f", ($0 - 0.5) * 200) })
            ]
        case "Detail":
            return [
                ("Structure", $editor.structure, 21, { String(format: "%+.0f", ($0 - 0.5) * 200) }),
                ("Sharpen", $editor.sharpen, 21, { String(format: "%+.0f", ($0 - 0.5) * 200) })
            ]
        default:
            return []
        }
    }

    /// One per row, inset from both edges.
    ///
    /// The gutters are not margin. A barrel takes any horizontal drag that starts
    /// on it, so a stack of edge-to-edge barrels leaves nowhere to begin a scroll
    /// except on something that might turn instead. The inset gives both thumbs a
    /// strip of panel that is only ever a scroll — belt and braces alongside the
    /// axis rule, which handles the drags that do start on a barrel.
    ///
    /// Three across was the other extreme: about 100pt each, barely two stops, and
    /// a barrel showing only its current value is a label with knurling on it.
    private func barrelBank(
        _ controls: [(String, Binding<Double>, Int, (Double) -> String)]
    ) -> some View {
        VStack(spacing: 13) {
            ForEach(Array(controls.enumerated()), id: \.offset) { index, control in
                EditBarrel(
                    label: control.0,
                    position: control.1,
                    stops: control.2,
                    format: control.3
                )
                .id(index)
            }
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 22) {
            ForEach(["Light", "Color", "Detail", "Film", "Crop"], id: \.self) { name in
                Button {
                    Haptics.tap()
                    withAnimation(.snappy(duration: 0.2)) { tab = name }
                } label: {
                    VStack(spacing: 4) {
                        Text(name)
                            .font(.ui(12, .semibold))
                            .foregroundStyle(tab == name ? Accent.amber : Tone.quaternary)
                        Rectangle()
                            .fill(tab == name ? Accent.amber : .clear)
                            .frame(height: 2)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var panel: some View {
        switch tab {
        case "Light", "Color", "Detail":
            barrelBank(barrelControls)

        case "Film":
            VStack(alignment: .leading, spacing: 16) {
                // Eleven stocks will not sit in a fixed row any more than they sat
                // in a barrel.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FilmPreset.all) { preset in
                            Chip(title: preset.name, isActive: preset.id == editor.filmID) {
                                Haptics.detent()
                                withAnimation(.snappy(duration: 0.2)) { editor.filmID = preset.id }
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
                SliderRow(
                    label: "Intensity",
                    value: "\(Int(editor.intensity * 100))%",
                    position: $editor.intensity
                )
                HStack(spacing: 8) {
                    Chip(title: "Grain", isActive: editor.grain) { Haptics.toggle(); editor.grain.toggle() }
                    Chip(title: "Halation", isActive: editor.halation) { Haptics.toggle(); editor.halation.toggle() }
                    Chip(title: "Vignette", isActive: editor.vignette) { Haptics.toggle(); editor.vignette.toggle() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default: // Crop
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    ForEach(PhotoEditor.cropOptions, id: \.self) { name in
                        Chip(title: name, isActive: editor.crop == name) {
                            Haptics.detent()
                            withAnimation(.snappy(duration: 0.2)) { editor.crop = name }
                        }
                    }
                }
                HStack(spacing: 8) {
                    Chip(title: "Rotate 90°", isActive: false) { Haptics.detent(); editor.rotate() }
                    Chip(title: "Reset", isActive: false) { Haptics.toggle(); editor.reset() }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Photo editor
//
// Holds the in-flight edit for one library photo. Rendering runs on a background
// queue and publishes a preview; doing CoreImage work inside `body` would stall
// the main thread on every slider tick, which is the failure mode this app spent
// a long time recovering from.

final class PhotoEditor: ObservableObject {

    static let cropOptions = ["Original", "1:1", "4:5", "16:9"]

    @Published private(set) var preview: UIImage?

    // Sliders are 0…1 so they can drive SliderRow directly; 0.5 is "no change"
    // for the bipolar ones.
    @Published var exposure: Double = 0.5 { didSet { scheduleRender() } }
    @Published var contrast: Double = 0.5 { didSet { scheduleRender() } }
    @Published var highlights: Double = 0.5 { didSet { scheduleRender() } }
    @Published var shadows: Double = 0.5 { didSet { scheduleRender() } }
    @Published var blackPoint: Double = 0.5 { didSet { scheduleRender() } }
    @Published var saturation: Double = 0.5 { didSet { scheduleRender() } }
    @Published var vibrance: Double = 0.5 { didSet { scheduleRender() } }
    @Published var temperature: Double = 0.5 { didSet { scheduleRender() } }
    @Published var tint: Double = 0.5 { didSet { scheduleRender() } }
    @Published var structure: Double = 0.5 { didSet { scheduleRender() } }
    @Published var sharpen: Double = 0.5 { didSet { scheduleRender() } }
    @Published var filmID: String = "amber" { didSet { scheduleRender() } }
    @Published var intensity: Double = 0 { didSet { scheduleRender() } }
    @Published var grain = false { didSet { scheduleRender() } }
    @Published var halation = false { didSet { scheduleRender() } }
    @Published var vignette = false { didSet { scheduleRender() } }
    @Published var crop = "Original" { didSet { scheduleRender() } }
    @Published private(set) var quarterTurns = 0

    var canSave: Bool { source != nil }

    var exposureEV: Double { (exposure - 0.5) * 4 }
    var contrastValue: Double { 0.5 + contrast }
    var saturationValue: Double { saturation * 2 }
    var kelvinValue: Double { ((3000 + temperature * 6000) / 100).rounded() * 100 }
    /// Green ↔ magenta, the axis white balance alone cannot reach.
    var tintValue: Double { (tint - 0.5) * 150 }
    /// Recovery is signed: negative pulls highlights down, positive opens shadows.
    var highlightValue: Double { (0.5 - highlights) * 2 }
    var shadowValue: Double { (shadows - 0.5) * 2 }
    var blackPointValue: Double { (blackPoint - 0.5) * 0.18 }
    var vibranceValue: Double { (vibrance - 0.5) * 2 }
    /// Large-radius unsharp mask: local contrast rather than edge definition.
    var structureValue: Double { (structure - 0.5) * 2 }
    var sharpenValue: Double { (sharpen - 0.5) * 2 }

    private var source: CIImage?
    private var sourceScale: CGFloat = 1
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let noiseTile = CameraManager.makeNoiseTile()
    private let renderQueue = DispatchQueue(label: "com.latitude.editor", qos: .userInitiated)
    private var pending: DispatchWorkItem?

    // MARK: Loading

    /// `image` overrides the photo's own — used to hand the editor the
    /// full-resolution roll copy once it arrives, without changing what photo is
    /// considered loaded (film id, source scale) in the meantime.
    func load(_ photo: PhotoGallery.Photo?, image: UIImage? = nil) {
        guard let photo, let cg = (image ?? photo.image).cgImage else {
            source = nil
            preview = nil
            return
        }
        source = CIImage(cgImage: cg)
        sourceScale = (image ?? photo.image).scale
        filmID = photo.filmID          // triggers the first render
    }

    func rotate() {
        quarterTurns = (quarterTurns + 1) % 4
        scheduleRender()
    }

    func reset() {
        exposure = 0.5
        contrast = 0.5
        highlights = 0.5
        shadows = 0.5
        blackPoint = 0.5
        saturation = 0.5
        vibrance = 0.5
        temperature = 0.5
        tint = 0.5
        structure = 0.5
        sharpen = 0.5
        intensity = 0
        grain = false
        halation = false
        vignette = false
        crop = "Original"
        quarterTurns = 0
        scheduleRender()
    }

    // MARK: Rendering

    private var params: Params {
        Params(
            ev: exposureEV, contrast: contrastValue, saturation: saturationValue,
            kelvin: kelvinValue, tint: tintValue,
            highlights: highlightValue, shadows: shadowValue, blackPoint: blackPointValue,
            vibrance: vibranceValue, structure: structureValue, sharpen: sharpenValue,
            filmID: filmID, intensity: intensity,
            grain: grain, halation: halation, vignette: vignette,
            crop: crop, quarterTurns: quarterTurns
        )
    }

    /// Coalesces the burst of changes a drag produces into one render.
    private func scheduleRender() {
        guard let source else { return }
        pending?.cancel()

        let snapshot = params
        let scale = sourceScale
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let image = Self.render(
                source, params: snapshot, context: self.context, noise: self.noiseTile, scale: scale
            )
            DispatchQueue.main.async { self.preview = image }
        }
        pending = work
        renderQueue.asyncAfter(deadline: .now() + 0.02, execute: work)
    }

    /// The saved frame is the same pipeline as the preview — no second code path
    /// that could drift from what the user approved on screen.
    func flattened() -> UIImage? {
        guard let source else { return nil }
        return Self.render(source, params: params, context: context, noise: noiseTile, scale: sourceScale)
    }

    struct Params: Equatable {
        var ev: Double
        var contrast: Double
        var saturation: Double
        var kelvin: Double
        // Neutral by default: a Params that does not mention a control means that
        // control makes no change, so a caller can name only what it is testing.
        var tint: Double = 0
        var highlights: Double = 0
        var shadows: Double = 0
        var blackPoint: Double = 0
        var vibrance: Double = 0
        var structure: Double = 0
        var sharpen: Double = 0
        var filmID: String
        var intensity: Double
        var grain: Bool
        var halation: Bool
        var vignette: Bool
        var crop: String
        var quarterTurns: Int
    }

    static func render(
        _ source: CIImage,
        params: Params,
        context: CIContext,
        noise: CIImage?,
        scale: CGFloat
    ) -> UIImage? {
        var image = source

        if abs(params.ev) > 0.001 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: params.ev])
        }

        // Tone recovery before global contrast: pulling highlights back after
        // stretching them has less left to recover.
        if abs(params.highlights) > 0.001 || abs(params.shadows) > 0.001 {
            image = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": 1 + params.highlights,
                "inputShadowAmount": params.shadows,
                kCIInputRadiusKey: 12.0
            ])
        }

        image = image.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: params.contrast,
            kCIInputSaturationKey: params.saturation
        ])

        // Black point as a bias, which is what "crush" and "lift" actually are —
        // moving where zero sits rather than bending the curve around it.
        if abs(params.blackPoint) > 0.001 {
            let b = CGFloat(params.blackPoint)
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputBiasVector": CIVector(x: b, y: b, z: b, w: 0)
            ])
        }

        image = image.applyingFilter("CITemperatureAndTint", parameters: [
            // Tint is the second component: the green–magenta axis, which white
            // balance on its own cannot reach.
            "inputNeutral": CIVector(x: CGFloat(params.kelvin), y: CGFloat(params.tint)),
            "inputTargetNeutral": CIVector(x: 6500, y: 0)
        ])

        // Vibrance after saturation, and separate from it: it leans on the
        // channels furthest from grey, which is what leaves skin alone while
        // everything around it lifts.
        if abs(params.vibrance) > 0.001 {
            image = image.applyingFilter("CIVibrance", parameters: [
                kCIInputAmountKey: params.vibrance
            ])
        }

        // Same matrices the live viewfinder uses, so a look chosen while shooting
        // reproduces exactly here.
        if params.intensity > 0.001 {
            let t = CGFloat(min(max(params.intensity, 0), 1))
            let (fr, fg, fb) = CameraManager.filmVectors(params.filmID)
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CameraManager.lerp(CIVector(x: 1, y: 0, z: 0, w: 0), fr, t),
                "inputGVector": CameraManager.lerp(CIVector(x: 0, y: 1, z: 0, w: 0), fg, t),
                "inputBVector": CameraManager.lerp(CIVector(x: 0, y: 0, z: 1, w: 0), fb, t)
            ])
        }

        let beforeEffects = image.extent
        if params.halation {
            image = image
                .applyingFilter("CIBloom", parameters: [
                    kCIInputRadiusKey: 12.0, kCIInputIntensityKey: 0.7
                ])
                .cropped(to: beforeEffects)
        }

        if params.vignette {
            image = image.applyingFilter("CIVignette", parameters: [
                kCIInputRadiusKey: 1.4, kCIInputIntensityKey: 1.2
            ])
        }

        if params.grain, let noise {
            image = noise
                .cropped(to: image.extent)
                .applyingFilter("CIOverlayBlendMode", parameters: [
                    kCIInputBackgroundImageKey: image
                ])
        }

        // Detail last, so it sharpens the picture that was actually made rather
        // than one the later stages then move underneath it.
        if abs(params.structure) > 0.001 {
            // A wide radius is what separates local contrast from sharpening:
            // it works on regions, not edges.
            image = image.applyingFilter("CIUnsharpMask", parameters: [
                kCIInputRadiusKey: 12.0,
                kCIInputIntensityKey: params.structure * 0.8
            ])
        }

        if params.sharpen > 0.001 {
            image = image.applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: params.sharpen * 1.2
            ])
        }

        image = crop(image, to: params.crop)
        image = rotate(image, quarterTurns: params.quarterTurns)

        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: .up)
    }

    /// Height ÷ width, matching the crop chip labels.
    static func cropRatio(_ name: String) -> CGFloat? {
        switch name {
        case "1:1":  return 1
        case "4:5":  return 5.0 / 4.0
        case "16:9": return 9.0 / 16.0
        default:     return nil
        }
    }

    static func crop(_ image: CIImage, to name: String) -> CIImage {
        guard let ratio = cropRatio(name) else { return image }

        let extent = image.extent
        var width = extent.width
        var height = width * ratio
        if height > extent.height {
            height = extent.height
            width = height / ratio
        }

        let rect = CGRect(
            x: extent.minX + (extent.width - width) / 2,
            y: extent.minY + (extent.height - height) / 2,
            width: width,
            height: height
        )
        return image.cropped(to: rect)
    }

    static func rotate(_ image: CIImage, quarterTurns: Int) -> CIImage {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0 else { return image }

        let rotated = image.transformed(
            by: CGAffineTransform(rotationAngle: -CGFloat(turns) * .pi / 2)
        )
        // Rotation moves the extent off the origin; CGImage creation expects it
        // back at zero.
        return rotated.transformed(
            by: CGAffineTransform(translationX: -rotated.extent.minX, y: -rotated.extent.minY)
        )
    }
}
