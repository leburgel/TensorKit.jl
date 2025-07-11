"""
    TreeTransformer

Supertype for structures containing the data for a tree transformation.
"""
abstract type TreeTransformer end

struct TrivialTreeTransformer <: TreeTransformer end

struct AbelianTreeTransformer{T,I,N,F1,F2,F3,F4} <: TreeTransformer
    rows::Vector{Int}
    cols::Vector{Int}
    vals::Vector{T}
    structure_dst::FusionBlockStructure{I,N,F1,F2}
    structure_src::FusionBlockStructure{I,N,F3,F4}
end

struct GenericTreeTransformer{T,I,N,F1,F2,F3,F4} <: TreeTransformer
    matrix::SparseMatrixCSC{T,Int}
    structure_dst::FusionBlockStructure{I,N,F1,F2}
    structure_src::FusionBlockStructure{I,N,F3,F4}
end

function treetransformertype(Vdst, Vsrc)
    I = sectortype(Vdst)
    I === Trivial && return TrivialTreeTransformer

    N = numind(Vdst)
    F1 = fusiontreetype(I, numout(Vdst))
    F2 = fusiontreetype(I, numin(Vdst))
    F3 = fusiontreetype(I, numout(Vsrc))
    F4 = fusiontreetype(I, numin(Vsrc))

    if FusionStyle(I) isa UniqueFusion
        return AbelianTreeTransformer{sectorscalartype(I),I,N,F1,F2,F3,F4}
    else
        return GenericTreeTransformer{sectorscalartype(I),I,N,F1,F2,F3,F4}
    end
end

function TreeTransformer(transform::Function, Vdst::HomSpace{S},
                         Vsrc::HomSpace{S}) where {S}
    I = sectortype(Vdst)
    I === Trivial && return TrivialTreeTransformer()

    structure_dst = fusionblockstructure(Vdst)
    structure_src = fusionblockstructure(Vsrc)

    rows = Int[]
    cols = Int[]
    vals = sectorscalartype(sectortype(Vdst))[]

    for (row, (f1, f2)) in enumerate(structure_src.fusiontreelist)
        for ((f3, f4), coeff) in transform(f1, f2)
            col = structure_dst.fusiontreeindices[(f3, f4)]
            push!(rows, row)
            push!(cols, col)
            push!(vals, coeff)
        end
    end

    if FusionStyle(I) isa UniqueFusion
        return AbelianTreeTransformer(rows, cols, vals, structure_dst, structure_src)
    else
        ldst = length(structure_dst.fusiontreelist)
        lsrc = length(structure_src.fusiontreelist)
        matrix = sparse(rows, cols, vals, ldst, lsrc)
        return GenericTreeTransformer(matrix, structure_dst, structure_src)
    end
end

# braid is special because it has levels
function treebraider(::AbstractTensorMap, ::AbstractTensorMap, p::Index2Tuple, levels)
    return fusiontreetransform(f1, f2) = braid(f1, f2, levels..., p...)
end
function treebraider(tdst::TensorMap, tsrc::TensorMap, p::Index2Tuple, levels)
    return treebraider(space(tdst), space(tsrc), p, levels)
end
@cached function treebraider(Vdst::TensorMapSpace, Vsrc::TensorMapSpace, p::Index2Tuple,
                             levels)::treetransformertype(Vdst, Vsrc)
    fusiontreebraider(f1, f2) = braid(f1, f2, levels..., p...)
    return TreeTransformer(fusiontreebraider, Vdst, Vsrc)
end

for (transform, treetransformer) in
    ((:permute, :treepermuter), (:transpose, :treetransposer))
    @eval begin
        function $treetransformer(::AbstractTensorMap, ::AbstractTensorMap, p::Index2Tuple)
            return fusiontreetransform(f1, f2) = $transform(f1, f2, p...)
        end
        function $treetransformer(tdst::TensorMap, tsrc::TensorMap, p::Index2Tuple)
            return $treetransformer(space(tdst), space(tsrc), p)
        end
        @cached function $treetransformer(Vdst::TensorMapSpace, Vsrc::TensorMapSpace,
                                          p::Index2Tuple)::treetransformertype(Vdst, Vsrc)
            fusiontreetransform(f1, f2) = $transform(f1, f2, p...)
            return TreeTransformer(fusiontreetransform, Vdst, Vsrc)
        end
    end
end

# default cachestyle is GlobalLRUCache
