"""Flatten a filled AcroForm: paint each field's appearance into the page.

pypdf 4 has no flattening of its own (``auto_regenerate`` only sets
``/NeedAppearances``, which asks the viewer to redraw every field — undoing
appearances we built on purpose, like text shrunk to fit its box).  So, per
widget: take its normal appearance stream (the ``/AS`` state for checkboxes),
draw it at the widget's ``/Rect`` the way a viewer would (PDF 32000-1 §12.5.5),
then drop the widgets and the ``/AcroForm`` so nothing is left to edit.
"""

from pypdf import PdfWriter
from pypdf.generic import (
    ArrayObject,
    DecodedStreamObject,
    DictionaryObject,
    IndirectObject,
    NameObject,
)

_HIDDEN = 1 << 1
_NO_VIEW = 1 << 5


def _appearance_ref(writer: PdfWriter, annot: DictionaryObject):
    """The widget's normal appearance, as an indirect reference; None if it has none."""
    ap = annot.get("/AP")
    if ap is None:
        return None
    ap = ap.get_object()
    normal = ap.raw_get("/N") if "/N" in ap else None
    if normal is None:
        return None
    if "/BBox" not in normal.get_object():
        # A state dictionary (checkbox, radio): draw the state it is in
        state = annot.get("/AS")
        states = normal.get_object()
        if state is None or state not in states:
            return None
        normal = states.raw_get(state)
    if not isinstance(normal, IndirectObject):
        normal = writer._add_object(normal)
    return normal


def _placement(stream: DictionaryObject, rect) -> list[float]:
    """Matrix A mapping the appearance's transformed BBox onto the widget Rect."""
    x0, y0, x1, y1 = (float(v) for v in stream["/BBox"])
    a, b, c, d, e, f = (float(v) for v in stream.get("/Matrix", [1, 0, 0, 1, 0, 0]))
    corners = [(a * x + c * y + e, b * x + d * y + f) for x in (x0, x1) for y in (y0, y1)]
    tx0, tx1 = min(p[0] for p in corners), max(p[0] for p in corners)
    ty0, ty1 = min(p[1] for p in corners), max(p[1] for p in corners)
    rx0, rx1 = sorted(float(v) for v in (rect[0], rect[2]))
    ry0, ry1 = sorted(float(v) for v in (rect[1], rect[3]))
    sx = (rx1 - rx0) / (tx1 - tx0) if tx1 > tx0 else 1.0
    sy = (ry1 - ry0) / (ty1 - ty0) if ty1 > ty0 else 1.0
    return [sx, 0, 0, sy, rx0 - tx0 * sx, ry0 - ty0 * sy]


def _append_content(writer: PdfWriter, page, data: bytes) -> None:
    """Draw *data* over the page, isolated from the page's own graphics state."""
    before = DecodedStreamObject()
    before.set_data(b"q\n")
    after = DecodedStreamObject()
    after.set_data(b"Q\n" + data)
    contents = page.get("/Contents")
    existing = [] if contents is None else (
        list(contents) if isinstance(contents.get_object(), ArrayObject) else [contents]
    )
    page[NameObject("/Contents")] = ArrayObject(
        [writer._add_object(before), *existing, writer._add_object(after)]
    )


def flatten_form(writer: PdfWriter) -> None:
    """Paint every form field into its page and remove the form."""
    # Numbered across the document: pages may share one /Resources dictionary,
    # and a per-page count would let page 2's fields replace page 1's.
    count = 0
    for page in writer.pages:
        annots = page.get("/Annots")
        if annots is None:
            continue
        kept = ArrayObject()
        drawn: list[str] = []
        xobjects = None
        for ref in annots.get_object():
            annot = ref.get_object()
            if annot.get("/Subtype") != "/Widget":
                kept.append(ref)
                continue
            if int(annot.get("/F", 0)) & (_HIDDEN | _NO_VIEW):
                continue
            appearance = _appearance_ref(writer, annot)
            if appearance is None:
                continue
            stream = appearance.get_object()
            stream[NameObject("/Type")] = NameObject("/XObject")
            stream[NameObject("/Subtype")] = NameObject("/Form")
            if xobjects is None:
                resources = page.get("/Resources")
                if resources is None:
                    resources = DictionaryObject()
                    page[NameObject("/Resources")] = resources
                resources = resources.get_object()
                if "/XObject" not in resources:
                    resources[NameObject("/XObject")] = DictionaryObject()
                xobjects = resources["/XObject"].get_object()
            name = f"/FlatField{count}"
            count += 1
            xobjects[NameObject(name)] = appearance
            matrix = " ".join(f"{v:.6g}" for v in _placement(stream, annot["/Rect"]))
            drawn.append(f"q {matrix} cm {name} Do Q")
        if drawn:
            _append_content(writer, page, ("\n".join(drawn) + "\n").encode())
        if kept:
            page[NameObject("/Annots")] = kept
        else:
            del page["/Annots"]
    root = writer._root_object
    if "/AcroForm" in root:
        del root["/AcroForm"]
